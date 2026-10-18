#!/usr/bin/env bash
#
# project-screenshots.sh
#
# Capture live screenshots of project sites, optimise them and convert them to
# WebP for the hirawat.in "projects" page.
#
# Usage
#   ./scripts/project-screenshots.sh --all
#   ./scripts/project-screenshots.sh "TryAR=https://tryar.in" "Jute=https://jute.hirawat.in"
#   ./scripts/project-screenshots.sh --all --force --quality 85
#   ./scripts/project-screenshots.sh --all --verify https://hirawat.in
#
# Options
#   --all                Capture every project listed in scripts/projects.txt
#   --file <path>        Use a different project list (format: name | slug | url)
#   --out-dir <path>     Output directory (default: static/img/projects)
#   --force              Re-capture images that already exist
#   --quality <1-100>    WebP quality (default: 80)
#   --width <px>         Output width in pixels (default: 1280)
#   --viewport <WxH>     Browser viewport (default: 1440x900)
#   --wait <ms>          Virtual time budget per page (default: 12000)
#   --delay <seconds>    Pause between captures (default: 1)
#   --no-build           Skip the Hugo build check at the end
#   --verify <base-url>  Check that the deployed .webp files are reachable
#   -h, --help           Show this help
#
# What it does
#   1. Finds a headless Chromium (Playwright cache, Puppeteer cache, system Chrome)
#   2. Checks each URL is reachable (retries transient failures)
#   3. Screenshots the live page at the configured viewport
#   4. Resizes + converts to WebP with cwebp (falls back to macOS sips)
#   5. Prints a ready-to-paste {{< figure >}} snippet per project
#   6. Optionally runs `hugo` to verify the site still builds
#
# Notes learned the hard way
#   * Headless Chrome writes the screenshot only on exit; a killed run leaves no file.
#   * Raise --wait for JS-heavy sites; lazy content may still not render.
#   * Cookie banners are part of the live page and will appear in the capture.
#   * Some hosts (Cloudflare) rate-limit; --delay keeps captures polite.
#
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------- defaults ---
DEST_DIR="$ROOT/static/img/projects"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TMP_DIR="$TMP_BASE/project-screenshots"
LIST_FILE="$SCRIPT_DIR/projects.txt"

VIEWPORT_W=1440
VIEWPORT_H=900
OUT_WIDTH=1280
QUALITY=80
WAIT_MS=12000
RETRIES=3
DELAY=1
FORCE=0
DO_BUILD=1
VERIFY_BASE=""
LOAD_LIST=0
CUSTOM_FILE=""
TARGETS=""

# --------------------------------------------------------------- utilities ---
say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*" >&2; }
die()  { printf 'ERROR %s\n' "$*" >&2; exit 1; }
hr()   { printf '%s\n' "------------------------------------------------------------"; }

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

domain_of() {
  printf '%s' "$1" | sed -E 's~^[a-zA-Z]+://~~; s~/.*$~~; s~^www\.~~'
}

size_of() {
  if [ -f "$1" ]; then
    wc -c < "$1" | tr -d ' '
  else
    printf '0'
  fi
}

human_size() {
  local bytes="$1"
  if [ "$bytes" -ge 1048576 ]; then
    awk -v b="$bytes" 'BEGIN { printf "%.1f MB", b/1048576 }'
  elif [ "$bytes" -ge 1024 ]; then
    awk -v b="$bytes" 'BEGIN { printf "%.0f KB", b/1024 }'
  else
    printf '%s B' "$bytes"
  fi
}

# ------------------------------------------------------- browser discovery ---
BROWSER=""
BROWSER_ARGS=""

find_browser() {
  local p
  # 1. Playwright headless shell (fastest, no --headless flag needed)
  for p in "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-mac/headless_shell; do
    [ -x "$p" ] && BROWSER="$p"
  done
  [ -n "$BROWSER" ] && return 0

  # 2. Playwright full Chromium (needs --headless=new)
  for p in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
    [ -x "$p" ] && BROWSER="$p"
  done
  if [ -n "$BROWSER" ]; then BROWSER_ARGS="--headless=new"; return 0; fi

  # 3. Puppeteer "Chrome for Testing" / Chromium
  for p in "$HOME"/.cache/puppeteer/chrome/*/chrome-mac-*/"Google Chrome for Testing.app"/Contents/MacOS/*; do
    [ -x "$p" ] && BROWSER="$p"
  done
  for p in "$HOME"/.cache/puppeteer/chrome/*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
    [ -x "$p" ] && BROWSER="$p"
  done
  if [ -n "$BROWSER" ]; then BROWSER_ARGS="--headless=new"; return 0; fi

  # 4. System browsers
  for p in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  do
    [ -x "$p" ] && BROWSER="$p"
  done
  if [ -n "$BROWSER" ]; then BROWSER_ARGS="--headless=new"; return 0; fi

  return 1
}

find_encoder() {
  if command -v cwebp >/dev/null 2>&1; then
    CWEBP="$(command -v cwebp)"
    return 0
  fi
  if command -v sips >/dev/null 2>&1; then
    CWEBP=""
    return 0
  fi
  return 1
}

# ------------------------------------------------------------- primitives ---
check_url() {
  local url="$1" i=1 code
  while [ "$i" -le "$RETRIES" ]; do
    code="$(curl -s -L -o /dev/null --max-time 20 -w '%{http_code}' "$url" 2>/dev/null)"
    if [ "$code" = "200" ]; then
      return 0
    fi
    i=$(( i + 1 ))
    sleep 2
  done
  return 1
}

capture() {
  local slug="$1" url="$2"
  local png="$TMP_DIR/$slug.png" attempt=1
  while [ "$attempt" -le "$RETRIES" ]; do
    rm -f "$png"
    # shellcheck disable=SC2086
    "$BROWSER" $BROWSER_ARGS \
      --no-sandbox \
      --disable-gpu \
      --hide-scrollbars \
      --window-size="$VIEWPORT_W,$VIEWPORT_H" \
      --virtual-time-budget="$WAIT_MS" \
      --screenshot="$png" \
      "$url" > "$TMP_DIR/$slug.log" 2>&1
    if [ -s "$png" ]; then
      return 0
    fi
    warn "capture failed for $slug (attempt $attempt/$RETRIES) - see $TMP_DIR/$slug.log"
    attempt=$(( attempt + 1 ))
    sleep 2
  done
  return 1
}

optimize() {
  local src="$1" dst="$2"
  rm -f "$dst"
  if [ -n "$CWEBP" ]; then
    # -resize W 0 keeps the aspect ratio; metadata is stripped
    "$CWEBP" -quiet -q "$QUALITY" -m 6 -sharp_yuv -metadata none \
      -resize "$OUT_WIDTH" 0 "$src" -o "$dst"
  else
    sips -s format webp -s formatOptions "$QUALITY" \
      --resampleHeightWidthMax "$OUT_WIDTH" "$src" --out "$dst" >/dev/null 2>&1
  fi
  [ -s "$dst" ]
}

snippet() {
  local name="$1" slug="$2" url="$3"
  printf '\n## [%s](%s) {#%s}\n\n' "$name" "$url" "$slug"
  printf '{{< figure src="/img/projects/%s.webp" alt="%s website" caption="%s" loading="lazy" >}}\n' \
    "$slug" "$name" "$(domain_of "$url")"
}

# ------------------------------------------------------------------ parse ---
add_target() { # name|slug|url
  if [ -z "$TARGETS" ]; then TARGETS="$1"; else TARGETS="$TARGETS
$1"; fi
}

parse_list_file() {
  local file="$1" line name slug url
  [ -f "$file" ] || die "project list not found: $file"
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    name="$(printf '%s' "$line" | awk -F'|' '{print $1}' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    slug="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    url="$(printf '%s'  "$line" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$name" ] && continue
    if [ -z "$url" ]; then           # only two fields: name | url
      url="$slug"; slug=""
    fi
    [ -z "$slug" ] && slug="$(slugify "$name")"
    add_target "$name|$slug|$url"
  done < "$file"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all)          LOAD_LIST=1 ;;
    --file)         CUSTOM_FILE="${2:-}"; shift ;;
    --out-dir)      DEST_DIR="${2:-}"; shift ;;
    --force)        FORCE=1 ;;
    --quality)      QUALITY="${2:-}"; shift ;;
    --width)        OUT_WIDTH="${2:-}"; shift ;;
    --viewport)     VIEWPORT_W="${2%%x*}"; VIEWPORT_H="${2##*x}"; shift ;;
    --wait)         WAIT_MS="${2:-}"; shift ;;
    --delay)        DELAY="${2:-}"; shift ;;
    --no-build)     DO_BUILD=0 ;;
    --verify)       VERIFY_BASE="${2:-}"; shift ;;
    -h|--help)      usage; exit 0 ;;
    --*)            die "unknown option: $1 (try --help)" ;;
    *=*)            add_target "${1%%=*}|$(slugify "${1%%=*}")|${1#*=}" ;;
    *)              die "cannot parse argument: $1 (expected Name=https://url)" ;;
  esac
  shift
done

if [ "$LOAD_LIST" = "1" ] || { [ -z "$TARGETS" ] && [ -n "$CUSTOM_FILE" ]; }; then
  parse_list_file "${CUSTOM_FILE:-$LIST_FILE}"
fi

if [ -z "$TARGETS" ]; then
  usage
  exit 0
fi

# --------------------------------------------------------------- preflight ---
[ -n "$DEST_DIR" ] || DEST_DIR="$ROOT/static/img/projects"
mkdir -p "$DEST_DIR" "$TMP_DIR"

find_browser || die "no headless Chromium found. Install one with:
  npx playwright install chromium
  # or
  brew install --cask google-chrome"

find_encoder || die "no WebP encoder found. Install one with: brew install webp"

say "browser : $BROWSER"
if [ -n "$CWEBP" ]; then
  say "encoder : cwebp $(cwebp -version 2>/dev/null | head -1)"
else
  warn "cwebp not found - falling back to sips (slower, larger files). Install with: brew install webp"
  say "encoder : sips"
fi
say "viewport: ${VIEWPORT_W}x${VIEWPORT_H}  ->  webp width ${OUT_WIDTH}px, quality ${QUALITY}"
say "output  : $DEST_DIR"
hr

# ------------------------------------------------------------------- main ----
# Note: the loop runs in a subshell (piped), so the summary below is built
# from the filesystem rather than from counters.
printf '%s\n' "$TARGETS" | while IFS='|' read -r name slug url; do
  [ -z "$name" ] && continue
  dst="$DEST_DIR/$slug.webp"

  if [ -f "$dst" ] && [ "$FORCE" != "1" ]; then
    say "SKIP  $slug ($(human_size "$(size_of "$dst")") already exists - use --force to refresh)"
    continue
  fi

  if ! check_url "$url"; then
    warn "SKIP  $slug - $url is not reachable (HTTP 200 expected)"
    continue
  fi

  say "CAPTURE $name -> $url"
  if ! capture "$slug" "$url"; then
    warn "FAIL  $slug - screenshot could not be captured"
    continue
  fi

  if ! optimize "$TMP_DIR/$slug.png" "$dst"; then
    warn "FAIL  $slug - could not convert to WebP"
    continue
  fi

  bytes="$(size_of "$dst")"
  if [ "$bytes" -lt 3000 ]; then
    warn "SMALL $slug - only $(human_size "$bytes"); the page may have rendered blank"
  fi

  say "OK    $slug ($(human_size "$bytes"))"
  snippet "$name" "$slug" "$url"
  sleep "$DELAY"
done

# The loop above runs in a subshell (piped), so summarise from the filesystem.
say ""
hr
say "results in $DEST_DIR:"
ls -1 "$DEST_DIR"/*.webp 2>/dev/null | while read -r f; do
  printf '  %-24s %s\n' "$(basename "$f")" "$(human_size "$(size_of "$f")")"
done
total="$(du -ch "$DEST_DIR"/*.webp 2>/dev/null | tail -1 | cut -f1)"
[ -n "$total" ] && say "total: $total"

# ---------------------------------------------------------------- build ------
if [ "$DO_BUILD" = "1" ]; then
  hr
  if command -v hugo >/dev/null 2>&1; then
    say "verifying Hugo build ..."
    if ( cd "$ROOT" && hugo --minify --quiet ); then
      say "Hugo build OK"
    else
      warn "Hugo build failed - check the output above"
    fi
  else
    warn "hugo not found in PATH - skipping build check"
  fi
fi

# --------------------------------------------------------------- verify ------
if [ -n "$VERIFY_BASE" ]; then
  hr
  say "verifying deployed images at $VERIFY_BASE ..."
  printf '%s\n' "$TARGETS" | while IFS='|' read -r name slug url; do
    [ -z "$slug" ] && continue
    curl -s -o /dev/null --max-time 20 \
      -w "  $slug.webp -> %{http_code} (%{size_download} bytes)\n" \
      "$VERIFY_BASE/img/projects/$slug.webp"
  done
fi

hr
say "done. Screenshots saved to $DEST_DIR; intermediate PNGs are in $TMP_DIR"
