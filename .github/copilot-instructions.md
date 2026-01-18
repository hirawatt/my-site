# Copilot Instructions for my-site

## Project Overview
A personal portfolio website built with [Hugo](https://gohugo.io/) static site generator, using the [Ink theme](https://github.com/knadh/hugo-ink) (included as a git submodule). The site powers [hirawat.in](https://hirawat.in) and is deployed on [Cloudflare Pages](https://pages.cloudflare.com/).

## Architecture

### Directory Structure
- **`content/`** – Markdown content organized by section
  - `_index.md` – Homepage with bio and quick links
  - `posts/` – Blog posts with front matter: title, date, description, tags, draft status
  - `projects.md`, `about/` – Static pages with hierarchical sections
- **`layouts/`** – Hugo templates controlling site rendering
  - `_default/baseof.html` – Base layout wrapper (head, header, main, footer)
  - `_default/single.html`, `list.html` – Page and listing layouts (in theme)
  - `partials/` – Reusable components (header, footer, post-preview, paginator)
  - `shortcodes/` – Custom Hugo shortcodes (see Customizations below)
- **`static/`** – Static assets (CSS, JS, images, favicon)
- **`themes/hugo-ink/`** – Git submodule; theme provides default layouts and styles
- **`config.toml`** – Hugo configuration; controls base URL, theme, site params, social links
- **`data/month.yaml`** – Month names (i18n helper for theme)

### Key Configuration (config.toml)
- **Base URL**: `https://hirawat.in/`
- **Theme**: `hugo-ink` (git submodule)
- **Params**:
  - `avatar` – Profile image (saitama-128x128.webp)
  - `mermaid: true` – Enables Mermaid diagram syntax
  - `mode: "auto"` – Dark mode auto-detection
  - `featherIconsCDN: true` – CDN icons in header/footer
  - Social links array (twitter, etc.)

## Core Workflows

### Creating Content
1. **New post**: `hugo new posts/my-post.md` → generates from `archetypes/posts.md`
   - Required front matter: title, date, description, tags
   - Set `draft: false` to publish
2. **New page**: `hugo new pages/my-page.md` → generates from `archetypes/default.md`
3. **Homepage index**: Edit `content/_index.md` (includes quick links using `{{< ref >}}` shortcode)

### Local Development
```bash
hugo server
```
Runs dev server at http://localhost:1313 with hot reload.

### Building
```bash
hugo
```
Generates static site to `public/` directory. Cloudflare Pages watches main branch for auto-deployment.

## Customizations & Extensions

### Mermaid Diagram Support
**Custom render hook** in `layouts/_default/_markup/render-codeblock-mermaid.html`:
- Wraps code blocks with class="mermaid" for Mermaid.js
- Sets page flag `hasMermaid` to conditionally load script in head
- Usage in content: ` ```mermaid ... ``` `

### Empty Custom Shortcodes
- `layouts/shortcodes/github.html` – Prepared for future GitHub repo embed shortcode (not yet implemented)
- Current usage in content: `{{< ref >}}` for internal links (Hugo built-in)

### Theme Overrides
- Site-level `layouts/` directory shadows theme defaults
- `layouts/posts/single.html` – Custom post layout (if needed, otherwise uses theme's)
- Static CSS/JS can override theme in `config.toml` with `customCSS`, `customJS` params

## Development Conventions

### Front Matter Metadata
- **Posts** (archetypes/posts.md): title, description, date, lastmod, tags, draft
- **Pages** (archetypes/default.md): title, type="page"
- Draft posts are excluded from builds by default

### Internal Links
Use Hugo's `ref` shortcode for internal navigation:
```markdown
[Link text]({{< ref "/projects" >}} "title")
```

### Asset Paths
- Images in `static/img/` (e.g., `saitama-128x128.webp` for avatar)
- CSS/JS in `static/css/` and `static/js/`
- Feather icons via CDN (configured in params)

## Build & Deployment
- **Build tool**: Hugo (static generator, no runtime dependencies)
- **Deployment**: Cloudflare Pages (auto-deploys on main branch pushes)
- **Outputs**: `public/` directory (generated, not committed)
- **Git ignore**: `.hugo_build.lock`, `public/`

## External Dependencies
- **Mermaid.js** – CDN-loaded (diagram rendering, enabled via config param)
- **Feather Icons** – CDN-loaded (icons, enabled via config param)
- **Hugo-ink theme** – Git submodule (https://github.com/knadh/hugo-ink)

---

*Last updated: 2026-01-19*
