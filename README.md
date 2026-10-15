# hirawat.in

Source code for [hirawat.in](https://hirawat.in) — the personal website, blog and portfolio of **Vishal Hirawat**.

Built with [Hugo](https://gohugo.io/) (extended) using a customized copy of the [Ink](https://github.com/knadh/hugo-ink) theme, and deployed to [Cloudflare Pages](https://pages.cloudflare.com/).

## Tech stack

| Area | Choice |
| --- | --- |
| Static site generator | [Hugo](https://gohugo.io/) (extended) |
| Theme | [hugo-ink](https://github.com/knadh/hugo-ink) — git submodule, customized |
| Hosting & CDN | [Cloudflare Pages](https://pages.cloudflare.com/) |
| Icons | [Feather](https://feathericons.com/) (CDN) |
| Diagrams | [Mermaid.js](https://mermaid.js.org/) (CDN) |

## Features

- Blog posts with tags, reading time, RSS feed and pagination
- Static pages: projects, links, glossary and "uses"
- [Mermaid.js](https://mermaid.js.org/) diagrams inside ` ```mermaid ` code blocks
- Automatic light/dark mode with a manual toggle
- SEO metadata: canonical URLs, sitemap, `robots.txt`, Open Graph and Twitter cards
- Web app manifest and favicon

## Getting started

Prerequisites: [Hugo extended](https://gohugo.io/installation/) and Git.

```bash
git clone --recurse-submodules https://github.com/hirawatt/my-site.git
cd my-site
hugo server
```

Open <http://localhost:1313>. The dev server reloads on changes.

Already cloned without the theme? Fetch it with:

```bash
git submodule update --init --recursive
```

### Build

```bash
hugo --minify
```

The generated site is written to `public/` (git-ignored).

## Project structure

```
.
├── archetypes/      # Content templates used by `hugo new`
├── content/         # Markdown content
│   ├── _index.md    # Homepage
│   ├── posts/       # Blog posts (e.g. uses.md)
│   ├── projects.md  # Projects page
│   └── about/       # links, glossary
├── data/            # month.yaml — i18n helper for the theme
├── layouts/         # Template overrides (shadow the theme's defaults)
├── static/          # CSS, JS, images, favicon, manifest
├── themes/hugo-ink  # Theme (git submodule)
└── config.toml      # Site configuration
```

## Customizations over the Ink theme

**Added**

- Mermaid.js rendering for ` ```mermaid ` code blocks — custom render hook in
  `layouts/_default/_markup/render-codeblock-mermaid.html` plus a conditional script loader.

**Removed**

- Disqus comments.

Google Fonts and Google Analytics are disabled, and several site-level templates
(`layouts/index.html`, `layouts/partials/*`, etc.) override the theme defaults.

## Deployment

Cloudflare Pages builds the site from the `main` branch on every push.

- **Build command:** `hugo`
- **Output directory:** `public`
- Pin a specific release with the `HUGO_VERSION` environment variable for reproducible builds.

## Credits & license

Content © Vishal Hirawat. The [Ink](https://github.com/knadh/hugo-ink) theme is licensed under the MIT License.
