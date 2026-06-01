# Admin Panel + In-App PDF Viewer — Change Spec

**Date:** 2026-05-20
**Author:** Founder request (visual-parity walkthrough follow-up)
**Status:** Draft for review

This doc bundles two related changes:

1. **In-app PDF viewer** — so documents render inside the Flutter app instead of handing off to the OS browser.
2. **Admin panel** — a single web surface for uploads, toggles, and debug, scoped so it doesn't fight Zoho.

The two are independent and can ship in either order, but doing the admin panel first makes the PDF flow easier to demo end-to-end.

---

## Part 1 — In-App PDF Viewer

### Current behaviour

`lib/features/documents/documents_screen.dart` → `_open()` calls:

```dart
launchUrl(uri, mode: LaunchMode.externalApplication);
```

That hands the signed URL to the device's default browser / PDF reader. The investor leaves the app. On web this opens a new tab. On mobile it bounces to Chrome / Files / Adobe Reader.

### Target behaviour

Tapping a document tile pushes an in-app PDF route. The PDF renders inside the Growize chrome, with the app bar showing the document name and a download / share action in the top-right. Back arrow returns to the documents list.

### Implementation outline

1. **Add a route** `/documents/:id` in `lib/core/navigation/router.dart`, inside the existing shell. Pushes a new screen `PdfViewerScreen(documentId)`.
2. **Create** `lib/features/documents/pdf_viewer_screen.dart`. Fetches the document row by id (already in the Hive cache), pulls the signed URL, hands it to a PDF widget.
3. **Pick one PDF package** — recommendation:
   - `syncfusion_flutter_pdfviewer` — best quality, supports zoom / page jump / text selection, free for our use under the Syncfusion Community License (org revenue < $1M).
   - Fallback: `flutter_pdfview` — lighter, no community licensing concern, but no web support. If we need web rendering use `pdfx` (works on Flutter web via PDF.js).
4. **Web vs. mobile rendering** — Flutter web can't share a binary PDF widget with mobile. Either:
   - Use `pdfx` (works on all platforms), OR
   - Use `syncfusion_flutter_pdfviewer` on mobile + embed `<iframe>` on web (cleanest split).
5. **Update** `_open()` in `DocumentTile` to `context.push('/documents/${item.id}')` instead of `launchUrl`.
6. **Keep a fallback** — if the in-app viewer fails to render (corrupt PDF, network), show an inline error with a "Open in browser" button that falls back to the current `launchUrl` behaviour.
7. **Add a Download button** in the app bar — `launchUrl` with `LaunchMode.externalApplication` so the investor can save it. Many investors will want this.

### Effort

~1 dev-day for mobile + web with a single package. Add half a day if we split mobile / web.

### Acceptance criteria

- Tapping any document in the Documents screen opens it inside the app on iOS, Android, and Web.
- Back arrow returns to the documents list with no flicker.
- A "Download" action in the app bar exports the file via the OS share sheet (mobile) or triggers a browser download (web).
- If render fails, an inline error gives the investor a working external link.

---

## Part 2 — Admin Panel

### The framing question

You asked: *"is this overcomplicating?"* — No. A single web surface for upload + toggle + debug is the right shape for a small team. What *would* overcomplicate it is duplicating Zoho.

### The rule that keeps this sane

Every field in the system falls into one of three buckets:

| Bucket | Source of truth | Admin panel can… | Examples |
|---|---|---|---|
| **CRM-owned** | Zoho | Read + trigger resync (NOT edit) | Investor name / PAN / units owned / payout history / project allocations |
| **Supabase-owned** | Supabase tables | Full read + write | Document files, gallery photos, project banner image, app_config flags, support tickets, exit requests, marketplace deadline, marketplace sort order |
| **Derived** | Computed | Read only | Portfolio totals, contract progress %, "next payout" calc |

If a CRM-owned field looks wrong, you fix it in Zoho and hit Resync. You never edit it in the admin panel — that's the rule that stops the two systems drifting.

### What the admin panel does

**Section 1 — Investors (read-only)**

- Searchable list of all investors (name, email, ARL ID, KYC status, allocated units, total invested).
- "View in Zoho" deep link per row.
- "Impersonate" button → opens the app in a new tab logged in as that investor (for support / debugging). Requires a backend route that mints a short-lived signed JWT.
- "Resync from Zoho" button per row + a global "Resync all" button.

**Section 2 — Projects**

For each project (Xiaomi LLP, Samsung LLP, etc.):

- **From CRM (read-only, with Resync):** project name, location, status, units total / sold, expected return, subscription deadline.
- **Editable in panel (Supabase-owned):**
  - `cover_image_path` — upload the project detail hero banner (drag-drop, shows preview).
  - `marketplace_image` — upload the Explore tile image.
  - `is_listed_in_marketplace` — toggle on / off.
  - `marketplace_sort_order` — number input, controls Explore ordering.
  - **Gallery photos** — drag-drop multi-upload, each photo gets caption + taken-at date. Reorder by drag. Delete with confirm.
  - **Phase override** — manual override of the auto-computed phase ("Land Closed", "Greenhouse", etc.) for the 10-stage timeline, in case Zoho is behind on phase data.

**Section 3 — Documents**

- Upload UI: drag a PDF, pick the investor it belongs to (or "all investors" for prospectus-type docs), pick a category, set a display title.
- Lists existing documents per investor with delete / replace.
- Bulk upload: drag 50 PDFs at once with a CSV mapping (`investor_id, doc_title, doc_category, file_name`).

**Section 4 — App Config**

The `app_config` table is the home for all "toggle" flags. Admin panel exposes them as labelled toggles / number inputs rather than raw key-value rows:

- "Show tutorial on first sign-in" (bool)
- "Force update minimum version" (string, e.g. `1.2.0`)
- "Critical update" (bool — when true, version banner is non-dismissible)
- "Latest version" (the value the version-check endpoint returns)
- "Marketplace sample mode" (show demo tiles when the user has no allocations)
- Anything else you add later.

**Section 5 — Debug / Observability**

- Recent Sentry events (last 100, with severity, route, investor email).
- "Last Zoho sync" timestamp per object type (investors, projects, payouts).
- "Last login" timeline (from the `login_events` table that's already in the schema).
- Failed edge function invocations (consultation requests, exit requests, ticket creates).
- A "Send test notification" form to push a notification to any investor (useful when debugging the bell + activity screen).

**Section 6 — Tickets / Requests (existing tables, just a UI)**

- Support tickets queue (open / replied / resolved).
- Exit requests queue with approve / decline.
- Consultation requests from the Explore screen.
- Bank-change requests.

Each of these already has tables and edge functions — you just don't have a UI today, you're presumably reading them in Supabase Studio.

### What it does NOT do

- Does **not** edit investor PAN / address / units allocated. Zoho only.
- Does **not** edit payouts. Zoho only (payouts get pushed into Supabase via the Zoho sync).
- Does **not** create or delete investors. Onboarding is Zoho-side, the Supabase row gets created by the `onboard-investor` edge function.

### Build options — ranked by speed-to-value

1. **Retool** *(recommended for first version)* — connect Retool to your Supabase Postgres + Storage. Drag-and-drop UI builder. Sections 1–6 above are buildable in 3–5 days by one person. Pros: fast, no infra. Cons: monthly cost (~$10–50/user), Retool branding, and you're locked into their UI patterns.
2. **Supabase Studio + a thin Next.js page** — Studio already covers ~60% of Section 1–4 (you can edit rows / upload to buckets directly). Add a tiny Next.js page just for the workflows Studio is bad at (bulk doc upload, impersonation, "Resync all"). Pros: minimal new infra, no licence fees. Cons: more dev work than Retool.
3. **Build a custom Flutter Web admin** — same codebase, share theme. Pros: feels native. Cons: 3–4× the dev time of Retool. Don't do this unless you're sure the team will outgrow Retool.
4. **Lovable / v0 / Tooljet** — similar tradeoffs to Retool. Pick on team familiarity.

**My recommendation:** Start with Retool (or Lovable if you want owned hosting). Re-evaluate in 3 months once you know which sections you actually use. If 80% of your time is in one section, port just that one to a custom page.

### Sequencing — 4-week plan

| Week | Deliverable |
|---|---|
| 1 | Retool account, DB + storage connected, **Section 2 (Projects)** + **Section 3 (Documents)** live. Founder can upload banners and docs today. |
| 2 | **Section 4 (App Config)** + **Section 6 (Tickets / Requests)**. Now ops doesn't have to touch Supabase Studio. |
| 3 | **Section 1 (Investors)** with Zoho deep links + impersonation backend route. |
| 4 | **Section 5 (Debug / Observability)** + polish + permissions (founder = full, ops = no debug section). Document for whoever else needs access. |

In parallel, week 1 also ships the in-app PDF viewer (separate dev, doesn't block).

### Effort estimate

- In-app PDF viewer: ~1 dev-day.
- Retool admin panel (all 6 sections, single builder): ~3 dev-weeks.
- Backend support — 1 edge function for impersonation, 1 for "Resync from Zoho" trigger if not already exposed: ~3 dev-days.

Total: **roughly 4 weeks of one engineer, or 2 weeks of two engineers.**

---

## Locked decisions (founder, 2026-05-20)

1. **Admin users:** founder + up to 2 ops staff. Three seats total. Role model = `admin_full` (founder) and `admin_ops` (no Debug section, no impersonation). Retool's basic seat tier covers this.
2. **Zoho sync model:** keep push (webhook) as the primary, **add pull on-demand for the admin panel.** The "Resync" button calls a new edge function `resync-from-zoho` that pulls from the Zoho REST API and upserts into Supabase. This complements push — push handles continuous updates, pull handles "fix it now" when a webhook was missed or drift is suspected.
3. **PDF viewer licence:** any package is fine. Going with `syncfusion_flutter_pdfviewer` on mobile (best quality) + `pdfx` on web (so we don't need an iframe fallback).
4. **Impersonation:** ship in v1.1. v1 lays the foundation — the `impersonation_sessions` table, RLS policies, and an edge function stub — so v1.1 is purely UI + activating the JWT minting logic. No throwaway work.

---

## Sequenced backlog

Task IDs: `PDF-*` for the PDF viewer, `AP-*` for the admin panel (`AP-1x` infra, `AP-2x` projects/docs, `AP-3x` config/queues, `AP-4x` investors/debug, `AP-5x` impersonation foundation).

### Week 1

| ID | Task | Effort | Notes |
|---|---|---|---|
| PDF-1 | Add `pdf_viewer_screen.dart` + route `/documents/:id` | 0.5d | Single screen, takes `documentId`, loads from existing Hive cache. |
| PDF-2 | Add `syncfusion_flutter_pdfviewer` (mobile) + `pdfx` (web) deps, gated by `kIsWeb` | 0.25d | Add to `pubspec.yaml`, conditional import. |
| PDF-3 | Replace `launchUrl` in `DocumentTile._open()` with `context.push('/documents/${item.id}')` + keep `launchUrl` as render-failure fallback | 0.25d | Includes the "Open in browser" error state. |
| PDF-4 | App-bar Download action (mobile share sheet / web download) | 0.25d | Re-uses signed URL. |
| AP-10 | Retool account + workspace setup, connect Supabase Postgres + Storage | 0.5d | One-time infra. |
| AP-11 | Define `admin_full` / `admin_ops` Retool groups + invite the 3 users | 0.25d | |
| AP-20 | **Projects section** — list view, per-project edit page, image uploaders for `cover_image_path` + `marketplace_image`, marketplace toggle + sort order, manual phase override field | 2d | Highest-value section — unblocks you uploading banners today. |
| AP-21 | **Documents section** — single-file upload form (investor + category + title), document list with replace/delete, bulk CSV upload | 2d | |

**End of week 1:** PDF viewer shipping + you can upload banners and documents without touching Supabase Studio.

### Week 2

| ID | Task | Effort | Notes |
|---|---|---|---|
| AP-30 | **App Config section** — labelled toggles for tutorial flag, latest version, critical update, marketplace sample mode | 1d | Backed by `app_config` table. |
| AP-31 | **Tickets queue** — list / filter / reply / close | 1d | Uses existing `support_tickets` + `reply-ticket` edge function. |
| AP-32 | **Exit requests queue** — list / approve / decline | 0.75d | Uses existing `exit_requests` table. |
| AP-33 | **Consultation requests queue** — list / mark contacted | 0.5d | |
| AP-34 | **Bank-change requests queue** — list / approve / decline | 0.75d | |

### Week 3

| ID | Task | Effort | Notes |
|---|---|---|---|
| AP-12 | New edge function `resync-from-zoho` (params: `entity_type`, optional `entity_id`) — pulls from Zoho REST API, upserts into Supabase | 2d | Needs Zoho OAuth refresh token in Supabase Vault. |
| AP-40 | **Investors section** — searchable list, KYC status, units owned, "View in Zoho" deep link, per-row + global "Resync from Zoho" buttons | 1.5d | Reads from `investors` table + LLP join. |
| AP-41 | **Project gallery uploader** — multi-upload, caption + taken-at, drag-reorder, delete | 1.5d | Extends the AP-20 project edit page. |

### Week 4

| ID | Task | Effort | Notes |
|---|---|---|---|
| AP-42 | **Debug section** — last Zoho sync per entity type, recent Sentry events (via Sentry API), login_events timeline, failed edge function invocations | 2d | Founder-only (admin_ops role hidden). |
| AP-43 | "Send test notification" form — pushes a row into `notifications` for any investor | 0.5d | |
| AP-50 | **Impersonation foundation (v1.1 prep)** — create `impersonation_sessions` table, RLS policies (admin_full only), and `impersonate-investor` edge function stub that returns 501 Not Implemented | 1d | v1.1 just adds the JWT minting + the Retool button. |
| AP-90 | Polish, hand-off docs in `docs/ops/admin_panel_guide.md`, role permission audit | 1d | |

**Totals:**
- PDF viewer: 1.25 dev-days.
- Admin panel: 17.25 dev-days (~3.5 weeks for one engineer, ~2 weeks for two).
- Edge function work (AP-12, AP-50): ~3 dev-days included in the above.

### v1.1 — impersonation activation (separate release)

| ID | Task | Effort |
|---|---|---|
| AP-51 | Implement JWT minting in `impersonate-investor` edge function (short-lived, 15-min expiry, audit-logged to `impersonation_sessions`) | 1d |
| AP-52 | Add "Impersonate" button to the Investors section, opens app in new tab with the signed JWT | 0.5d |
| AP-53 | Banner inside the Flutter app when an impersonation session is active ("You are viewing as <name>. Exit"). | 0.5d |
| AP-54 | Security review + smoke test | 0.5d |

---

## What this unlocks for you

After **week 1** of this plan:
- Documents render in-app instead of bouncing to a browser.
- You can upload project banner + Explore tile images yourself, no Supabase Studio.
- You can upload investor documents (single + bulk).

After **week 2:** all ops queues (tickets, exits, consultations, bank changes) have a UI.

After **week 3:** the admin panel is genuinely one-stop — you stop opening Supabase Studio.

After **week 4:** debug tooling lets you triage issues without pinging a dev.

After **v1.1 (separate):** support staff can impersonate investors to reproduce bugs.

---

## Cross-references

- Decision log: `.claude/decisions/2026-05-20_admin-panel-and-pdf-viewer.md`
- Related ops docs (existing): `docs/ops/data_sources_guide.md`, `docs/ops/v1.1_roadmap.md`, `docs/ops_admin_guide.md` (predecessor — to be superseded by the new `docs/ops/admin_panel_guide.md` in AP-90).
