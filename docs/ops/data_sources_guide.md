# Growize App — Data Sources Guide

Where every visible piece of data in the Growize app comes from, who owns it, and what to do when it shows wrong / blank / "TBD" to an investor.

This guide is the answer to: *"I see X on screen Y but it's empty — where do I add the value?"*

Last updated: 2026-05-16 · v1.0 launch readiness

---

## Architecture in one paragraph

Zoho CRM is the source of truth for everything investor-related (Contacts), LLP-related (LLP_Creation_Module), and allocation-related (LLP_UnitAllocation_Module). When ops edits a record in Zoho, a workflow rule fires a Deluge Custom Function (CF) which POSTs to a Supabase edge function (`zoho-crm-webhook`). The handler mirrors data into Supabase Postgres tables, which the Flutter app reads via Riverpod providers + Supabase JS client. Hard delete in Zoho cascades to Supabase via ON DELETE CASCADE FKs.

So the rule for "I see wrong data on screen":
1. Check Supabase mirror first (via Supabase Dashboard → SQL editor)
2. If Supabase has the right value → bug is in the Flutter app
3. If Supabase has the wrong value → check Zoho source field
4. If Zoho has the right value but Supabase doesn't → webhook sync issue (check `webhook_log` table)

---

## Screen → data source map

### Home / Dashboard

| UI element | Data source | Status |
|---|---|---|
| Investor name | `investors.name` ← Zoho Contact First/Last Name | Live |
| Project switcher | `investor_units` JOIN `projects` for the logged-in investor | Live |
| Sync badge ("Live" / "Syncing") | Supabase realtime subscription state on `investor_units` | Live |
| Total units owned | SUM(investor_units.units) for investor | Live |
| Total invested | SUM(units × unit_price) | Live |
| Expected return | Avg of project annual_yield_pct weighted by units | Live |
| Next payout date | MIN(payouts.payout_date) WHERE date > today | Live |

**To fix any of these:** if data is wrong, check the underlying allocation in Zoho's LLP_UnitAllocation_Module record. If the Supabase mirror lags, check `webhook_log` for failed events.

---

### Projects tab — list

| UI element | Data source | Status |
|---|---|---|
| Project card name | `projects.name` ← Zoho LLP Name | Live |
| Project card image | `projects.marketplace_image` ← Zoho LLP Marketplace_Image URL field | Live, but most LLPs don't have it set yet — **action needed** |
| Investor's units in this project | SUM(investor_units.units) for this project | Live |
| Status pill (Active / Closed / etc.) | derived from `projects.subscription_deadline` + units_available | Live |

**To set a project's hero photo:** open the LLP record in Zoho → upload an image to the `Marketplace_Image` field (URL string field; upload elsewhere if your Zoho doesn't have file fields, paste the URL). Webhook syncs to `projects.marketplace_image` within ~30s.

---

### Projects tab — detail screen (lean overview)

| UI element | Data source | Status |
|---|---|---|
| Hero banner image | `projects.marketplace_image` | Live (see above) |
| Tier badge (Premium / Standard) | `projects.tier` ← Zoho LLP Tier picklist | Live — **action needed**: confirm picklist values are set per LLP |
| Your Investment stats | `investor_units` + `payouts` for this investor + project | Live |
| Current Phase tile | `projects.current_phase` ← latest `project_phases` row | Live; see `docs/ops/project_phases_guide.md` for how to update |
| 6-stage phase timeline | `project_phases` rows for this project, ordered by `stage_order` | Live |
| Recent payouts | `payouts` where investor_id = current, ordered desc | Live |
| Monthly Updates accordion | `project_updates` table (if exists) — **TBD: confirm table exists** | Mock / placeholder |
| Documents tile | `documents` count for this project + investor | Live |
| Single-line projection callout | hardcoded text using `projects.expected_annual_return_pct` | Live |

---

### Projects tab — View Area sub-screen (NEW)

This screen is the "geography + property" deep-dive accessed via the "View Area" action tile.

| UI element | Data source | Status |
|---|---|---|
| Map preview | `projects.latitude`, `projects.longitude` + ±200m jitter | **Mock for v1.0** — no real coords stored yet. **Action needed**: add lat/lng to LLP records in Zoho, then add columns to Supabase + webhook mapping |
| Radius circle (no pinpoint) | derived: ~500m-1km radius | Rendered client-side; not a data source |
| "Within 3 km of <town>" tag | `projects.nearest_town` ← Zoho LLP Address_Line_1_City (approx) | Live in mock; verify post-launch |
| Growing Method (Aeroponic / Hydroponic) | `projects.growing_method` | **Mock — column doesn't exist yet** |
| Water Saved % | `projects.water_efficiency_pct` | **Mock — column doesn't exist yet** |
| Annual Yield (kg/m²) | `projects.annual_yield_kg_per_sqm` | **Mock — column doesn't exist yet** |
| Harvest Cycles per year | `projects.harvest_cycles_per_year` | **Mock — column doesn't exist yet** |
| Pesticide-Free badge | `projects.is_pesticide_free` BOOLEAN | **Mock — column doesn't exist yet** |
| Climate Controlled badge | `projects.is_climate_controlled` BOOLEAN | **Mock — column doesn't exist yet** |
| Tech Stack one-liner | `projects.tech_stack` TEXT | **Mock — column doesn't exist yet** |
| Certification chips (FSSAI / Organic / GAP) | `projects.certifications` TEXT[] or JSONB | **Mock — column doesn't exist yet** |
| Crops Grown list | `projects.crops_grown` TEXT[] | **Mock — column doesn't exist yet** |
| Climate Control summary | `projects.climate_summary` TEXT | **Mock — column doesn't exist yet** |
| Acreage / Property | `projects.acreage_acres` (exists) + new `projects.cultivated_acres` | acreage Live; cultivated TBD |

**Action plan to wire growing-tech data:**

1. **Add new columns** to `projects` table (single migration):
   - `growing_method TEXT`
   - `water_efficiency_pct INTEGER` (e.g. 95)
   - `annual_yield_kg_per_sqm INTEGER` (e.g. 32)
   - `harvest_cycles_per_year INTEGER` (e.g. 8)
   - `is_pesticide_free BOOLEAN DEFAULT false`
   - `is_climate_controlled BOOLEAN DEFAULT false`
   - `tech_stack TEXT`
   - `certifications JSONB` (e.g. `["FSSAI", "Organic", "GAP"]`)
   - `crops_grown JSONB` (e.g. `["Strawberries", "Basil", "Lettuce"]`)
   - `climate_summary TEXT`
   - `latitude DOUBLE PRECISION`
   - `longitude DOUBLE PRECISION`
   - `nearest_town TEXT`
   - `cultivated_acres DOUBLE PRECISION`

2. **Add corresponding fields** to Zoho's LLP_Creation_Module (one per column, matching naming convention).

3. **Update `Push_LLP_To_Supabase` Deluge CF** to include the new fields in the payload (use the same flat-field pattern that was used for `Address_Line_1_*`).

4. **Update Supabase `zoho-crm-webhook` handler** (`handleProject`) to read the new fields off `d` and write them to the projects upsert. Use the dual-read pattern (`d.growing_method || d.Growing_Method`) for resilience.

5. **Populate values per project** in Zoho. Suggested values (verify with the agronomy team):
   - EKA: Aeroponic, 95%, 32 kg/m², 8 cycles, strawberries+basil, FSSAI+Organic+GAP
   - Sunrise: Hydroponic, 88%, 25 kg/m², 6 cycles, leafy greens, FSSAI+Organic
   - Verdant: Vertical Aeroponic, 96%, 38 kg/m², 9 cycles, microgreens+herbs, FSSAI+Organic+GAP

Until step 5 lands, the View Area screen will show placeholder values from `lib/core/mock/mock_data.dart`.

---

### Projects tab — Photos sub-screen (NEW)

| UI element | Data source | Status |
|---|---|---|
| Photo grid | `gallery_photos` table WHERE project_id = current | Live, but needs photos uploaded |
| Photo file URLs | Supabase storage bucket `arl-gallery` | Live |
| Fullscreen lightbox | Pure UI; no data | N/A |

**To add photos:** ops uploads to `arl-gallery` bucket via Supabase Dashboard → Storage. Then INSERT into `gallery_photos` with the project_id + storage path. (Future: build an ops-side admin tool to do this without SQL.)

---

### Explore tab — tile grid

| UI element | Data source | Status |
|---|---|---|
| Tile hero image | `projects.marketplace_image` | Live; see Projects detail above |
| Status pill (Open / Coming soon / Sold out) | derived: `units_available`, `total_units`, `subscription_deadline` | Live |
| Project name | `projects.name` | Live |
| Location | `projects.city` + `projects.state` | Live |
| Crop type chip | `projects.crop_type` ← Zoho LLP Crop_Type | Live — **action needed** to ensure picklist values are filled |
| Fill bar | `(total_units - units_available) / total_units` | Live |
| Price per unit | `projects.price_per_unit` ← Zoho LLP Unit_Price | Live |

**Filter pills (All / Open for Reservation / Coming soon)** are derived client-side from `projects.subscription_deadline` and the unit counts. No data source change needed.

**To add a new project to the marketplace:**
1. Create LLP in Zoho with LLP_Status = "Open for Reservation"
2. Set Unit_Price, Total_Units, Subscription_Deadline
3. Set Marketplace_Image URL
4. Webhook sync; project appears in Explore within ~30s

---

### Explore tab — detail screen (marketplace mode) (NEW)

| UI element | Data source | Status |
|---|---|---|
| Hero banner | `projects.marketplace_image` | Live |
| Marketplace stats (Units Available, Price, Return, Lock-in) | `projects.*` columns | Live except `min_lockin_months` |
| Min Lock-in | `projects.min_lockin_months` | **Mock — column doesn't exist yet** (add to migration above) |
| Growing Tech section | same mock columns as View Area | Mock |
| Mini map | same as View Area | Mock |
| Photos strip | `gallery_photos` | Live but needs photos |
| Request Consultation CTA | submits to `consultation_requests` table via existing edge function | Live |
| Share Project CTA | opens share modal | Live (modal renders from in-memory data; no new data source) |

---

### Share Project modal (NEW)

| UI element | Data source | Status |
|---|---|---|
| Project image, name, location, stats | Same as Explore detail | Live or mock per above |
| RM name | env var / constant | **Hardcoded for v1.0** — see `lib/core/constants/rm_contact.dart` (to be created) |
| RM photo | constant asset path | **Hardcoded — add to `assets/rm.jpg`** |
| RM WhatsApp number | env var | **Hardcoded for v1.0** |
| Growize tagline | constant | Hardcoded |

**For v1.0:** all RM info hardcoded. For v1.1+: add `rm_contacts` table with `rm_id`, `name`, `phone`, `photo_url`, plus `investors.rm_id` FK so each investor gets their assigned RM.

---

### Financials tab

| UI element | Data source | Status |
|---|---|---|
| Portfolio summary | `portfolio_summary` view (Supabase) — aggregates investor_units + payouts | Live |
| Payouts list | `payouts` WHERE investor_id = current, ORDER BY payout_date DESC | Live |
| Exit history | `exit_requests` WHERE investor_id = current | Live |
| Risk vs Return chart | computed client-side from investor's allocations | Live (kept; only the 5-year projection chart was removed) |

The removed 5-year projection chart is replaced with a single-line text using `projects.expected_annual_return_pct`.

---

### Documents tab

The Documents tab renders two scopes, in this order:

**Project Documents** (migration `054_project_documents`, added 2026-05-25) — LLP agreements, brochures, quarterly reports. Single row per file in `public.project_documents`. RLS scopes reads to investors with a non-zero (`issued_units > 0`), non-deleted row in `investor_units` for the same project, OR rows with `is_public = true` (visible to all authenticated users).

**Personal Documents** — the existing `public.documents` table (KYC, contracts, payout receipts). One row per investor per file. RLS scopes to `investor_id = auth.uid()` plus the legacy tier system in `032`/`033`.

| UI element | Data source | Status |
|---|---|---|
| Project Documents (grouped by project) | `project_documents` (RLS-filtered) | Live |
| Project group header (name + unit count) | `projects.name` + SUM(`investor_units.issued_units`) | Live |
| Project doc category pill | `project_documents.category` | Live |
| Personal document list (grouped by tier) | `documents` WHERE investor_id = current OR project_id IN (...) | Live |
| Tier (KYC / Legal / Project-specific) | `documents.visibility` | Live |
| In-app PDF viewer | reads from Supabase storage `arl-documents` bucket | Live |

**When to use which table?**

| Scenario | Use this | Why |
|---|---|---|
| LLP agreement, project brochure, quarterly investor report | `project_documents` (new) | One file shared across N investors — one row, no fan-out |
| Investor's signed contract, KYC packet, individual payout receipt | `documents` (existing) | Distinct per-investor file, RLS-scoped to `investor_id` |
| Company-wide briefing (no project context) | `project_documents` with `is_public = true` | Skips the allocation check; visible to every authenticated user |
| Legacy "common" tier in `documents` | Don't add new rows here | Migration `054` supersedes the tier system for shared docs |

#### Where do project documents live?

- **Storage bucket:** `arl-documents` (shared with personal documents — different table, same bucket)
- **Table:** `public.project_documents` (migration `054`, added 2026-05-25)
- **RLS:** `is_public = true` OR investor has `investor_units` row with `issued_units > 0` and `deleted_at IS NULL` in the same project

#### Upload workflow (ops, via Supabase Studio)

1. **Upload the PDF.** Supabase Studio → Storage → `arl-documents` → Upload. Convention: `<project-slug>/<filename>.pdf` (e.g. `pineapple-enterprises/llp-agreement-v3.pdf`). Slashes inside the object name create folders automatically.
2. **Add the catalog row.** Supabase Studio → Table Editor → `project_documents` → Insert row:
   - `project_id` — the UUID from `public.projects` (look up by name first)
   - `storage_path` — the path inside the bucket, exactly as in step 1 (no leading `/`, no bucket name)
   - `title` — display name shown to investors (e.g. "LLP Agreement v3")
   - `category` — one of `agreement` / `brochure` / `report` / `certification` / `financial` / `regulatory` / `update`. Falls back to `general` if blank.
   - `is_public` — leave `false` unless this is a company-wide briefing
   - `sort_order` — `10`, `20`, `30`… (lower = earlier in the list). Use multiples of 10 so future rows can slot in without renumbering.
   - `uploaded_at` defaults to `now()` — leave alone unless backdating
3. **No per-investor row needed.** Every investor with a non-zero allocation in `project_id` will see the file automatically on next pull-to-refresh. There is **no** N-row fan-out — one upload, N viewers.
4. **Verify in the app.** Sign in as a test investor with units in that project → Documents tab → the file should appear under the "PROJECT DOCUMENTS" section, grouped under the project name.

If the bytes are missing but the row exists, the row still renders in the list — tapping it shows "Document URL unavailable" via the existing signed-URL fallback. The opposite (file present, row missing) hides it from the app entirely.

---

### Gallery tab

| UI element | Data source | Status |
|---|---|---|
| Photo grid | `gallery_photos` for all projects investor has units in | Live |
| Lazy-loaded images | Supabase storage `arl-gallery` | Live |

Same pattern as Photos sub-screen, but aggregated across all the investor's projects.

---

### Activity tab

| UI element | Data source | Status |
|---|---|---|
| Notification cards | `notifications` WHERE investor_id = current ORDER BY created_at DESC | Live |
| Read status | `notifications.read_at` | Live |
| Tap routing | `notifications.metadata` JSONB (contains project_id, allocation_id, etc.) | Live |

Notifications are inserted by edge functions on events (payout processed, KYC status change, allocation created, etc.). To trigger one manually: `INSERT INTO notifications (investor_id, type, title, body, metadata) VALUES (...)`.

---

### Profile tab

| UI element | Data source | Status |
|---|---|---|
| Display name, email, phone | `investors.*` ← Zoho Contact | Live |
| KYC status | `investors.kyc_status` | Live |
| Bank details (masked) | `investors.bank_account_masked` etc. ← Zoho Contact Bank fields | Live |
| Edit name flow | submits update → mirrors back to Zoho via `Push_Contact_Update_To_Supabase` CF | Live |
| Bank change request | submits to `bank_change_requests` via `bank-change-request` edge function | Live |
| KYC re-submission | submits to `kyc_resubmissions` table | Live |
| Privacy Policy / Terms | static screens in `lib/features/profile/privacy_policy_screen.dart` / `terms_screen.dart` | Live |
| Preview First-Payout Celebration (NEW) | hardcoded test data passed to `/celebration` route | Dev/preview only |
| Logout | clears Supabase session | Live |

---

### Celebration screen (NEW)

| UI element | Data source | Status |
|---|---|---|
| Confetti illustration | static SVG / CustomPainter in app | N/A |
| "Your first payout has arrived" | static copy | N/A |
| Amount + currency | passed as route query param (amount=41000) | Live; trigger reads from `payouts` table |
| Project name | passed as query param (project=EKA) | Live |
| Payout date | passed as query param (date=2026-03-15) | Live |
| "Maybe later" / "View in Financials" / "Share" CTAs | route navigation | Live |
| First-payout-seen flag | `investors.first_payout_seen BOOLEAN` | **NEW column needed** — add via migration |

**Trigger condition:** Home screen on first build checks `payouts.count > 0` AND `investors.first_payout_seen == false`. If both true, push to `/celebration` with the first payout's data, then UPDATE `investors.first_payout_seen = true`.

---

### Auth screens (login / OTP)

| UI element | Data source | Status |
|---|---|---|
| Magic link request | `request-auth-email` edge function (server-side allow-list) | Live |
| OTP verify | Supabase Auth `verifyOTP` | Live |
| Forgot password | same `request-auth-email` with mode=reset | Live |

Only registered emails (those mirrored from Zoho Contacts) receive emails. Unregistered emails get identical "ok" response with NO email sent (enumeration protection).

---

## Common ops scenarios

### "An investor's payout isn't showing in the app"

1. Check `payouts` table: `SELECT * FROM payouts WHERE investor_id IN (SELECT id FROM investors WHERE email = '<email>') ORDER BY created_at DESC LIMIT 10`
2. If missing: check `webhook_log` for `LLP_UnitAllocation_Module.edit` events around the allocation update time
3. If event exists but failed: read `error_message`
4. If event missing: check Zoho's allocation record — did `UTR_N`, `Amount_N`, `Date_N` get filled and a workflow rule fire?

### "A project's hero image isn't showing"

1. Check `SELECT name, marketplace_image FROM projects WHERE name LIKE '%<project>%'`
2. If NULL: open the LLP in Zoho, paste a URL into `Marketplace_Image` field, save
3. Within 30s, check Supabase again — should be populated
4. If still NULL after sync: check `webhook_log` for that LLP's recent events

### "A project's growing tech / View Area data is wrong"

For v1.0 these are mock values from `lib/core/mock/mock_data.dart`. To make them real, follow the action plan in the **Projects tab — View Area** section above.

### "Two investors received different versions of the app"

Web URL = always latest deploy on Netlify. APK = whatever was emailed. If you've deployed a new APK, ask the investor to install the latest version via the email link. There's no in-app update prompt for v1.0 (add in v1.1).

---

## Tables reference (quick lookup)

| Table | Source | Purpose |
|---|---|---|
| `investors` | Zoho Contacts | Investor profile + KYC + bank |
| `llps` | Zoho LLP_Creation_Module | LLP entity data |
| `projects` | Zoho LLP_Creation_Module | Project mirror (1:1 with LLPs today) |
| `project_phases` | Zoho LLP_Status timeline | Phase progression rows |
| `investor_units` | Zoho LLP_UnitAllocation_Module | Allocations |
| `payouts` | Zoho LLP_UnitAllocation_Module UTR fields | Payouts (unpacked from slots 1-10) |
| `documents` | Manual upload + Zoho doc URLs | Investor + project documents |
| `gallery_photos` | Manual upload | Project photos |
| `notifications` | App-generated | In-app notifications |
| `consultation_requests` | App-generated | Explore "Request Consultation" submissions |
| `bank_change_requests` | App-generated | Bank detail change requests |
| `kyc_resubmissions` | App-generated | KYC re-upload requests |
| `support_tickets` | App-generated | Support tickets (both form + WhatsApp-hybrid) |
| `exit_requests` | App-generated | Investor exit requests |
| `webhook_log` | Zoho-generated | Sync audit trail |
| `auth.users` | Supabase Auth | Authentication |

---

## When in doubt

Read `lib/features/<feature>/<feature>_screen.dart` — the Riverpod provider import at the top usually points at the data source. Then `Cmd+Click` the provider name to see the query.

If a UI element shows "TBD" or is empty:
- 90% of the time the field exists but isn't populated in Zoho
- 9% of the time the field exists but the webhook hasn't synced (check webhook_log)
- 1% of the time it's a real Flutter bug

Start with the data, not the code.

---

## v33 — Phase data + Slack/email + Notifications

> **[ACCURACY WARNING — added 2026-08-22]**
>
> Sections 1 and 3 below describe a system that **does not exist in this
> repository**. Every item listed here was checked against the codebase on
> 2026-08-22 and found missing:
>
> | Documented below | Actual state |
> |---|---|
> | `handleLlp()` in `zoho-crm-webhook/index.ts` | no such function |
> | `phase_timeline_10.dart` | does not exist — the widget is `phase_timeline_6.dart` (class name kept for source-stability; it does render 10 stages) |
> | `supabase/migrations/2026-05-19_phase_backfill.sql` | does not exist |
> | `supabase/migrations/2026-05-19_documents_notify_trigger.sql` | does not exist |
> | `notify_document_insert()` | not in any migration file (note: a `notify_document_uploaded()` IS referenced by migration 060, so the live DB may hold functions this repo does not) |
> | `project_phases.stage_index` / `stage_name` / `reached_at` / `source` | real columns are `phase_name`, `status`, `phase_date`, `sub_items`, `sort_order`, `started_at`, `completed_at` |
> | notification types `phase_update`, `new_project`, `document` | none were legal until migration 066 (2026-08-22) — `documents-sync` had been emitting `document` and Postgres had been silently rejecting every insert |
> | `Phase_1..Phase_10` date + notes fields on `LLP_Creation_Module` | the live EKA LLP record carries none of these 20 fields |
>
> What IS true as of migration 066: `project_phases` rows now drive the
> stage timeline, and flipping a row to `current` fans out a
> `phase_update` notification. There is still **no Zoho sync handler** for
> phase data — stage rows must be written directly (see
> `scripts/eka_stage_update.sql`). Push notifications remain unbuilt; see
> `docs/plans/2026-08-22_push_notifications_fcm_scope.md`.
>
> Treat the rest of this section as a design sketch, not a description of
> running code.


Added 2026-05-20 to capture the data flows that landed during the v33 design refresh / edge-function upgrade.

### 1. 10-stage Zoho phase data flow

The Project Detail screen's phase timeline expanded from 6 to 10 stages in v33 to match Zoho's `LLP_Status` taxonomy. Path of a phase change from Zoho to the app:

```
Zoho LLP_Creation_Module
  ├─ LLP_Status picklist (10 values: Land Identified → Land Closed →
  │   Soil Test → Construction → Greenhouse Ready → Planting →
  │   Harvest → Operational → Compliance Closed → Go-live)
  ├─ Phase_<n>_Date fields (10 per LLP, one per stage)
  └─ Phase_<n>_Notes fields (10 per LLP, free-text)
       │
       ▼ Deluge custom function (Push_LLP_To_Supabase)
       │   Fires from LLP_Creation_Module workflow rule on
       │   "edit any field" — packs all 20 phase fields into the JSON body
       │   keyed by phase_1..phase_10.
       │
       ▼ Supabase edge function (zoho-crm-webhook v32)
       │   handleLlp() in supabase/functions/zoho-crm-webhook/index.ts
       │   1. Upserts the LLP row → llps + projects.
       │   2. For each non-null Phase_<n>_Date, upserts a row into
       │      project_phases (PRIMARY KEY: project_id, stage_index).
       │      stage_index = n (1..10).
       │   3. When LLP_Status crosses to a new stage, emits a
       │      notification row of type='phase_update' for every
       │      investor in investor_units for that project.
       │
       ▼ Supabase table: project_phases
       │   columns: project_id (FK), stage_index (int 1..10),
       │   stage_name (text), reached_at (timestamptz),
       │   notes (text), updated_at, source ('zoho').
       │
       ▼ Flutter app
           lib/features/projects/widgets/phase_timeline_10.dart
           reads via projectPhasesProvider(projectId) →
           supabase.from('project_phases').select().eq('project_id', id)
           ordered by stage_index. Renders 10 stage dots; current = last
           non-null reached_at. Past = check icon; future = muted dot.
```

**Backfill:** A one-time SQL backfill (`supabase/migrations/2026-05-19_phase_backfill.sql`) migrated the old 6-stage rows to the 10-stage schema by mapping prior `stage_index` values into the new indices and inserting null placeholders for the new compliance/go-live rows. Ops can re-trigger by re-saving each LLP in Zoho (the Deluge CF fires on edit).

### 2. Consultation Slack/email fan-out

The Explore "Request Consultation" button writes a row to `consultation_requests` and fans out to Slack + email so RMs get notified without polling Supabase.

```
Flutter Explore Detail screen
  ▼ lib/features/explore/explore_detail_screen.dart
    supabase.from('consultation_requests').insert({
      investor_id, project_id, name, phone, requested_at
    })
       │
       ▼ Supabase trigger: notify_consultation_request_trigger
       │   AFTER INSERT ON consultation_requests
       │   FOR EACH ROW EXECUTE FUNCTION notify_consultation_request().
       │   The function calls supabase.functions.invoke(
       │     'notify-consultation-request', body=NEW row
       │   ) via the pg_net extension.
       │
       ▼ Edge function: notify-consultation-request (v3, 2026-05-19)
           supabase/functions/notify-consultation-request/index.ts
           1. Reads NEW.name (NOT full_name — v3 fix; v2 read the wrong
              key and posted "undefined" into Slack).
           2. Posts a formatted block to SLACK_WEBHOOK_URL with
              investor name, phone, project name, project hero thumb.
           3. Sends an HTML email via Resend (RESEND_API_KEY) to
              CONSULTATION_NOTIFY_EMAIL (comma-separated list).
           4. Returns 200 even on partial failure so the trigger does
              not block the insert.
```

### 3. Life-event notifications

`zoho-crm-webhook v32` writes notifications rows for three life-events. Each one is gated so duplicate webhook deliveries don't double-fire (uses the row's natural key + a timestamp window).

| Event | Fires when | Source row | Notification type |
|---|---|---|---|
| New project | New row in `llps` from Zoho webhook AND the LLP is marked `Is_Listed_In_Marketplace=true` | `llps` (insert from webhook) | `new_project` (broadcast to all active investors) |
| Phase update | `LLP_Status` field changes in Zoho → handler upserts project_phases AND detects a NEW stage_index for the project | `project_phases` (insert with new stage_index) | `phase_update` (to every investor in investor_units for the project) |
| Document upload | `documents` table receives an INSERT (either ops manual upload OR Zoho doc URL sync) | `documents` (insert) | `document` (to the document's owner_id investor — or all project investors if owner_id is NULL and project_id is set) |

The document path also fires from a Supabase trigger on `documents INSERT` (not from the webhook directly) — see migration `2026-05-19_documents_notify_trigger.sql`. The trigger function `notify_document_insert()` is tier-aware: premium investors get a richer notification body (`title` + `body_html` with project hero thumbnail) while standard investors get the plain `title` + `body` pair.

### 4. Required Supabase secrets

Set these in Supabase → Project settings → Edge Functions → Secrets before deploying any of the edge functions above:

| Secret | Used by | Purpose |
|---|---|---|
| `SUPABASE_URL` | All edge functions | Project URL (auto-set by Supabase, but required for invokes from triggers) |
| `SUPABASE_SERVICE_ROLE_KEY` | All edge functions | Server-side queries that bypass RLS |
| `SLACK_WEBHOOK_URL` | notify-consultation-request | Slack channel webhook for #ops-consultations |
| `RESEND_API_KEY` | notify-consultation-request | Resend transactional email API key |
| `CONSULTATION_NOTIFY_EMAIL` | notify-consultation-request | Comma-separated To: list for consultation emails |
| `ZOHO_WEBHOOK_SECRET` | zoho-crm-webhook | Bearer token Zoho sends in `Authorization` header; rejects payloads without it |
| `ZOHO_API_TOKEN` | zoho-reconcile-daily | OAuth refresh token for Zoho CRM (used only by the nightly reconcile job) |

### 5. Required Zoho field list (20 phase fields)

`LLP_Creation_Module` must expose these fields for the 10-stage timeline to work. Names are case-sensitive and must be wired into the `Push_LLP_To_Supabase` Deluge CF JSON body keys.

| # | Stage name | Date field | Notes field |
|---|---|---|---|
| 1 | Land Identified | `Phase_1_Date` | `Phase_1_Notes` |
| 2 | Land Closed | `Phase_2_Date` | `Phase_2_Notes` |
| 3 | Soil Test | `Phase_3_Date` | `Phase_3_Notes` |
| 4 | Construction | `Phase_4_Date` | `Phase_4_Notes` |
| 5 | Greenhouse Ready | `Phase_5_Date` | `Phase_5_Notes` |
| 6 | Planting | `Phase_6_Date` | `Phase_6_Notes` |
| 7 | Harvest | `Phase_7_Date` | `Phase_7_Notes` |
| 8 | Operational | `Phase_8_Date` | `Phase_8_Notes` |
| 9 | Compliance Closed | `Phase_9_Date` | `Phase_9_Notes` |
| 10 | Go-live | `Phase_10_Date` | `Phase_10_Notes` |

The `LLP_Status` picklist must have these 10 exact string values too — the webhook handler does a case-sensitive comparison to compute the "current stage" pointer.

