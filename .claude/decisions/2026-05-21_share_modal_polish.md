# Share Modal — Polish Pass

**Status:** locked
**Date:** 2026-05-21
**File:** `lib/features/explore/widgets/share_project_modal.dart`

## Problem

After the 2026-05-21 share fix that wired the buttons up, the preview
modal swung too far toward minimal — investor feedback was that the
screen looked "blank and bleak." The 280x420 cream card sat on a
cream modal background with three tiny stat labels in the lower half
and no anchor for the eye. It read as a placeholder, not a share-
ready artifact.

## Fix

Polish without re-cluttering. Keep the same three buttons and the
same data fields; rebuild the visual hierarchy so the preview card
reads as something a user would want to actually post.

### Modal chrome

- Background: swapped pure cream #FAFAF7 to warm-stone #F2F1E8 so
  the cream card now has contrast and lifts off the surface. Defined
  as the `_modalSurface` const at the top of state.
- Drag handle: 36x4 sand pill at top-center, Material-standard.
- Header: small `Icons.share_outlined` (16pt primary) + title
  "Share this project" (16pt SemiBold charcoal) + close X right.
  Header divider line removed.
- Sheet radius bumped 20 -> 22.

### Preview card

- Frame: 280x420 cream card with a 2px gold border and a stronger
  shadow `BoxShadow(50,0,0,0) blur 24 offset (0,10)`.
- Hero: fills top 55% (231px). The previous gradient + overlaid
  name/location are removed — that content now lives below where it
  has room to breathe.
- Body hierarchy (top-down):
  1. Project name — Inter SemiBold 19pt charcoal, 1 line.
  2. Location row — 11pt `location_on_outlined` accent icon + muted
     11pt text, 4px below the name.
  3. Thin sand divider — 60% width minus padding, left-aligned,
     12px above and below.
  4. Three stat blocks — each with a small accent/gold icon
     (`dashboard_outlined`, `grass_outlined`, `workspace_premium`),
     9pt uppercase muted label with 0.5 letter-spacing, 14pt
     SemiBold charcoal value.
  5. Gold annual-return pill — `+N% Expected Annual Return`,
     centered gold-filled rounded pill with a soft glow shadow.
     The value-prop hook.
  6. Cream-to-sand gradient bottom strip (30px) with `growize`
     wordmark (11pt SemiBold primary) and a small `eco_outlined`
     accent leaf on the right.

### Caption + buttons

- Caption: `maxLines: 3 / minLines: 2`, white fill, 1px sand border,
  12-radius, primary 1.4px focus border. Hint ends in `...`.
- WhatsApp: 48px, #25D366 fill, white text/icon 16pt, 12-radius,
  with a soft brand-green drop shadow via an outer `DecoratedBox`.
- Copy share link: 48px, outlined primary, white fill, `Icons.link`.
- More sharing options: 44px (visibly down-weighted), sand border,
  muted text, transparent fill, `Icons.ios_share`.
- Button gap 10px.

## Trade-offs

- Single-line project name (was 2-line in the hero overlay). The new
  layout is laid out tight (hero 231px + body 189px). Long names
  truncate cleanly with ellipsis.
- Annual-return pill is driven by `expectedAnnualReturnPct` from the
  model. Falls back to a static label if 0.
- No PNG export yet — the card is a widget; WhatsApp/Copy still
  send a text message with the URL.

## Files touched

- `lib/features/explore/widgets/share_project_modal.dart` — full
  rewrite of `build`, `_header`, `_sharePreviewCard`, `_statBlock`
  (was `_miniStat`), `_captionField` (extracted), `_shareButtons`;
  added `_dragHandle` and `_modalSurface` const. Public API
  unchanged — all existing callers still compile.

## Verify

`& C:\flutter\bin\dart.bat analyze lib` — could not run in the
Linux sandbox (Flutter is Windows-only here). Run on the host
before shipping. Visual sanity checks: 715 lines, two top-level
classes properly closed (lines 75 and 715), enum intact (line 17),
three button handlers (`_shareWhatsApp`, `_copyLink`, `_shareNative`)
all present and unchanged from previous fix.
