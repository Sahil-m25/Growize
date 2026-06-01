# In-App Document Viewer + Screenshot Prevention

**Date:** 2026-05-21 (filed 2026-05-23 — backdated to the feedback session)
**Status:** Locked
**Trigger:** Investor feedback — "documents should open inside the app, not in an external browser, and they shouldn't be screenshottable."

---

## Problem

`lib/features/documents/documents_screen.dart` -> `_DocRow._open()` called
`launchUrl(uri, mode: LaunchMode.externalApplication)` on the signed
Supabase URL. That handed off to Chrome / Files / Adobe Reader and
the investor left the Growize chrome. The signed URL was also
trivially shareable from the browser address bar and there was
nothing stopping screenshots while the document was on screen.

## Decision

Render documents inside the Flutter app via a new full-screen route
`DocumentViewerScreen`, with platform-native screenshot prevention
enabled for the lifetime of that screen. The previous `launchUrl`
fallback is removed from the documents list — keeping it would
defeat the whole point (the investor could still bounce out).

## Packages added

| Package | Version | Why |
|---|---|---|
| `syncfusion_flutter_pdfviewer` | ^27.1.48 | High-quality PDF rendering on mobile + web (canvas). Community Edition is Apache 2.0 and free under Syncfusion's < $1M-revenue threshold. Zoom, page nav, scroll-status indicator built in. |
| `screen_protector` | ^1.5.0 | Sets Android `FLAG_SECURE` while the viewer is mounted (screenshot returns "Screenshot blocked by app", screen-record shows a black frame) and, on iOS, blurs the snapshot during app-switcher / screen recording. |
| `http` | ^1.2.2 | Pinned (transitively present via supabase_flutter) — used to fetch signed-URL bytes for the "Save to in-app library" action. |

Justification for adding three new packages in one PR: the user
requirement ("inside the app, can't be screenshotted, can be
downloaded to internal memory") is non-negotiable. Each package
serves one of the three sub-requirements; none could be removed
without dropping a requirement. Images reuse `cached_network_image`
(already in pubspec), no new package needed for them.

## Scope of screenshot prevention

Applied only to `DocumentViewerScreen`, not globally. Reason:
blanket `FLAG_SECURE` would also block screenshots that investors
want (portfolio summary for their accountant, support ticket
detail to share with us, etc.). The investor's request was
specifically about documents — protect what's sensitive, leave the
rest open.

`initState` -> enable; `dispose` -> disable. Both calls are wrapped
in try/catch so a plugin failure can't crash the viewer.

## Web caveat

`screen_protector` is a no-op on Flutter web — browsers don't
expose any API equivalent to `FLAG_SECURE`. The Print Screen key
will continue to capture. The PDF still renders in-app (Syncfusion
on web uses canvas), so the "inside the app" requirement is met;
the "can't screenshot" half is best-effort only. Documented here
because the investor will use web at some point and we don't want
to claim a guarantee we can't enforce.

## File layout

- `lib/features/documents/document_viewer_screen.dart` — new screen.
  Resolves the doc from `documentsProvider` (or accepts a preloaded
  `InvestorDocument`), determines the file type from the URL extension,
  routes to a Syncfusion PDF viewer, a `CachedNetworkImage` inside
  `InteractiveViewer`, or a "preview not supported" fallback.
- `lib/features/documents/documents_screen.dart` — `_DocRow._open()`
  now `Navigator.push`es the viewer (fullscreenDialog: true) instead
  of calling `launchUrl`. `url_launcher` import removed.
- `lib/core/navigation/router.dart` — added
  `${RouteNames.documentViewer}/:id` GoRoute outside the shell so the
  viewer is full-screen (no bottom-nav strip eating canvas space).
- `lib/core/navigation/route_names.dart` — added `documentViewer`
  constant + `documentViewerPath(id)` helper.
- `pubspec.yaml` — three new dependencies.

## Edge cases handled

- Signed URL expired between list fetch and tap. `_PdfBody` catches
  `onDocumentLoadFailed`, invalidates `documentsProvider`, refetches,
  and retries once with the new URL. Only after the second failure
  does the user see an error snackbar.
- Unknown file type. Anything that isn't pdf / jpg / png / webp /
  gif / bmp shows a friendly "preview not supported" panel with a
  download button — the file is still saved locally, just not
  rendered.
- Empty signed URL (offline cache miss). Fallback panel asks the
  user to pull-to-refresh the Documents tab. Download button is
  disabled because there's nothing to fetch.
- Web platform. `kIsWeb` guards every `dart:io` / `Platform.X` call;
  the viewer renders, download stays in-memory (no silent disk write
  is possible from a browser context anyway).

## Download flow

Tapping the AppBar download icon fetches the signed URL with
`package:http`, writes the bytes to
`getApplicationDocumentsDirectory()` — internal app storage that
isn't surfaced in the device file manager. Filename is sanitized to
strip path-traversal characters. A "Saved to in-app library"
snackbar confirms. A future iteration can index these local files
and surface them under a "Saved" tab; today they're write-only.

## What we did NOT do

- Did not apply `FLAG_SECURE` app-wide. See "Scope" above.
- Did not wire an "Open in external browser" escape hatch on PDF
  render failure. The whole point is to keep the document inside the
  app — if Syncfusion can't render it, the investor sees an error
  and can download the file or contact support.
- Did not strip the existing `url_launcher` dep — it's used
  elsewhere (Share Project modal, support links).
- Did not ship the wider v1.1 admin-panel/PDF spec
  (`docs/plans/2026-05-20_admin_panel_and_pdf_viewer_spec.md`). This
  is the PDF viewer slice only; the admin panel waits.

## Verification

- `dart analyze lib` deferred — Cowork sandbox does not have the
  Flutter SDK on PATH. Local run command:
  `& C:\flutter\bin\dart.bat analyze lib`.
- Manual test plan:
  - Android: tap any document -> opens in-app, attempt screenshot ->
    "Screenshot blocked by app" toast, start screen recording -> the
    document portion of the recording is black, tap download ->
    toast "Saved to in-app library".
  - Web (Chrome): tap any document -> opens in-app inside Syncfusion's
    canvas-rendered viewer; screenshot is NOT blocked (platform
    limitation, see "Web caveat").
