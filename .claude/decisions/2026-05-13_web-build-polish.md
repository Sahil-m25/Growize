# Web build polish

**Date:** 2026-05-13
**Status:** locked
**Phase:** Implement (ship readiness)

## Context
The default Flutter web scaffold ships with placeholder `name`,
`short_name`, `<title>`, and `description` strings (`"arl_app"`,
`"A new Flutter project."`). For a private-but-real launch, the
manifest + index.html + robots posture all need to reflect the brand
and the distribution model — investors landing on the deployed URL
should see `Growize` everywhere, and the site should not be indexed by
search engines.

## Decision

### `web/manifest.json`
- `name` → `Growize — ARL Investor Portal`
- `short_name` → `Growize`
- `description` → `Private investor portal for Agri Research Labs
  agricultural projects.`
- `theme_color` → `#3C5152` (design-token `primary`)
- `background_color` → `#FAFAF7` (design-token `cream`)
- Icons untouched (`flutter_launcher_icons` generates these from
  `assets/images/arl_logo.png` during pub run).

### `web/index.html`
- `<title>` → `Growize — ARL Investor Portal`
- `<meta name="description">` matches the manifest description.
- `<meta name="theme-color" content="#3C5152">` for browser chrome
  tinting.
- `<meta name="viewport">` widened to include `viewport-fit=cover`
  for notched displays.
- `<meta name="robots" content="noindex, nofollow, noarchive">` —
  private portal, no crawl. Belt-and-braces alongside `robots.txt`.
- `apple-mobile-web-app-title` → `Growize`.
- `apple-mobile-web-app-status-bar-style` → `black-translucent` so
  Add-to-Home-Screen looks closer to the native bundle's status bar.
- `lang="en"` set on `<html>` (was missing).

### `web/robots.txt` (new)
```
User-agent: *
Disallow: /
```
Disallows all crawlers from indexing any path. Search engines that
honour the spec (Google, Bing, DuckDuckGo) will skip the site
entirely.

### Favicon
- Existing `web/favicon.png` is retained. `flutter_launcher_icons`
  regenerates it from `assets/images/arl_logo.png` on next pub run if
  needed — no manual swap required for this commit.

## Build verification

Production build was attempted with a throw-away placeholder
`.env.production` (populated with non-real values) to satisfy the
`isConfigured` assertion in release mode. The build:

```
flutter build web --release --dart-define-from-file=.env.production
```

Succeeded:

```
Compiling lib\main.dart for the Web...                             95.6s
√ Built build\web
```

Tree-shaking reduced `MaterialIcons-Regular.otf` from 1.65 MB → 15.5 KB
(99.1 % saving). The `cupertino_icons` "Expected to find fonts for"
warning is a known Flutter web cosmetic — the package ships its own
font lookup, the icons render correctly, and the warning does not
break the build.

The placeholder `.env.production` was deleted post-build (only
`.env.example` remains tracked).

## Hosting decision (deferred to user)

`build/web/` is the deploy target. Options outlined in
`docs/ops_admin_guide.md` §8.4: Netlify drop, Vercel, Firebase
Hosting, S3 + CloudFront. Recommendation: Netlify drop for the
first iteration — zero-config, single-URL, HTTPS by default, drag
the `build/web/` folder into the dashboard. Switch to S3 + CloudFront
if cost or vendor concentration becomes a concern.

## Verification
- `flutter build web --release --dart-define-from-file=.env.production`
  succeeded.
- `web/manifest.json`, `web/index.html`, `web/robots.txt` reviewed
  visually.
- Placeholder `.env.production` removed post-build (gitignored anyway).
