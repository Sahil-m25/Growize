# ARL Investor Portal — Data Flow Guide

This document describes, end-to-end, where every piece of investor data
lives and how it moves between Zoho CRM, Supabase, and the Flutter app
(`com.arl.app`). It is the working reference for any developer or ops
person who needs to debug a missing value, add a new field, or onboard
a new investor.

The source-of-truth is Zoho CRM. Supabase is a read-optimised mirror
maintained by two paths — a real-time webhook (push) and a daily
reconcile cron (pull). The Flutter app reads exclusively from Supabase.

---

## 1. Top-level architecture

```
                                Zoho CRM (org: ARL)
                                ┌────────────────────────────────────────┐
                                │  Contacts                              │
                                │  LLP_Creation_Module                   │
                                │  LLP_UnitAllocation_Module             │
                                └────────────────────────────────────────┘
                                          │
                            Workflow Rule on field-edit / create
                                          │
                                          ▼
                                Deluge custom functions
                                ┌────────────────────────────────────────┐
                                │ Push_Contact_To_Supabase               │
                                │ Push_LLP_To_Supabase                   │
                                │ Push_Allocation_To_Supabase            │
                                └────────────────────────────────────────┘
                                          │ HTTPS POST + X-ARL-Webhook-Secret
                                          ▼
       (Pull fallback, daily 01:00 UTC)   Supabase Edge Function
       ┌──────────────────────┐           ┌────────────────────────────────────────┐
       │ zoho-reconcile-daily │──────────►│ zoho-crm-webhook                       │
       │ (cron + Zoho REST)   │           │  └─ handleContact / handleProject /    │
       └──────────────────────┘           │     handleAllocation                   │
                                          └────────────────────────────────────────┘
                                          │
                                          ▼
                                Postgres tables (RLS enforced)
                                ┌────────────────────────────────────────┐
                                │ investors        ←  Contacts           │
                                │ llps             ←  LLP_Creation       │
                                │ projects         ←  LLP_Creation       │
                                │ investor_units   ←  LLP_UnitAllocation │
                                │ payouts          ←  UTR_1..10 fan-out  │
                                │ notifications    ←  side-effect insert │
                                │ webhook_log      ←  audit trail        │
                                │ auth.users       ←  onboard-investor   │
                                └────────────────────────────────────────┘
                                          │  PostgREST + JWT, RLS
                                          ▼
                                Flutter APK (com.arl.app)
                                ┌────────────────────────────────────────┐
                                │ Home  Projects  Financials  Explore    │
                                │ Activity  Profile  KYC  Bank           │
                                └────────────────────────────────────────┘
```

Sync-staleness observability is handled by `sync-stale-alert` (hourly
cron), which reads the `sync_status` view and writes a `sync_alerts` row
whenever any mirrored table's `max(last_synced_at)` exceeds its
per-table threshold.

---

## 2. The three sync paths

### 2.1 Contacts → `investors`

**Trigger.** Zoho workflow rule on the Contacts module fires on create
and on edit of monitored fields (KYC, PAN, bank, mailing address,
on-boarding flags).

**Deluge function.** `Push_Contact_To_Supabase` POSTs to
`/functions/v1/zoho-crm-webhook` with `X-ARL-Webhook-Secret` set. It
builds either an `envelope` body (`{module, operation, data:{…}}`) or a
flat / query payload — all four shapes are normalised by
`normaliseRequest()` in `zoho-crm-webhook/index.ts`.

**Handler.** `handleContact(supabase, d, modifiedTime)`
(`supabase/functions/zoho-crm-webhook/index.ts`).

1. Looks up the matching `investors` row by `zoho_contact_id = d.id`.
2. If no row exists, the handler **silently returns**
   (`onboard-investor` must run first — see Section 3).
3. If the stored `updated_at` is newer than `d.Modified_Time`, the
   handler returns (stale-write guard against out-of-order delivery).
4. Otherwise it `UPDATE`s the row.

**Coercions applied.**

- `mapKycStatus(d.KYC)` — Zoho picklist (`Pending`, `In Progress`,
  `Completed`, `Verified`, `Rejected`, `Not Started`) → canonical enum
  (`pending`, `in_progress`, `verified`, `rejected`). Unknown values
  fall back to `pending` so the `investors_kyc_status_check` CHECK
  constraint can never be violated.
- `maskPan(d.PAN_Number)` — `RTYUI2468L` → `RTYUI****L` (kept first 5,
  last 1; raw PAN never persists).
- `maskBankAccount(d.Bank_Account_Number)` — keeps last 4 digits, e.g.
  `XXXX-XXXX-9012`.
- Boolean flags compared strictly with `=== true`, so any Zoho payload
  that ships strings (`"true"`) collapses to `false`. That's why the
  reconcile cron deliberately **does not** round-trip the booleans —
  see `CONTACT_FIELDS` in `zoho-reconcile-daily/index.ts`.

**Resulting row.** A `public.investors` row with: `name`, `email`,
`phone`, `salutation`, `kyc_status`, `pan_masked`,
`bank_account_masked`, `bank_ifsc`, `bank_branch`, `bank_holder_name`,
`bank_name`, `address_line1/city/state/pincode/country`, the five
boolean flags (`unit_allocated`, `payment_received`,
`profile_verified`, `agreement_signed`, `fema_applicable`),
`updated_at`, `last_synced_at`.

**Flutter read.** `InvestorRepository.currentInvestor()`
(`lib/core/repositories/investor_repository.dart`) issues
`client.from('investors').select().limit(1).maybeSingle()` and lets
RLS pin the row to `id = auth.uid()`. Exposed via
`currentInvestorProvider` (`lib/core/providers/repositories.dart`).
Surfaces in: profile header (name, ARL ID, KYC dot), KYC screen, Bank
Details screen.

---

### 2.2 LLP_Creation_Module → `llps` + `projects`

**Trigger.** Zoho workflow rule on the LLP_Creation_Module fires on
create or on edit of any operational/financial field (status, total
units, pricing, insurance, launch year, addresses, SPOC).

**Deluge function.** `Push_LLP_To_Supabase`. Its emitted field set must
mirror the `LLP_FIELDS` constant in `zoho-reconcile-daily/index.ts` —
if either side adds a new field without the other, reconcile will
overwrite real CRM data with stale/empty values on its next pass.

**Handler.** `handleProject(supabase, d)` fans out **one** LLP record
into **two** Supabase rows:

1. **`llps` upsert** (legal/holding metadata). On-conflict key:
   `zoho_llp_id`. Columns written: `name`, `llp_status`, `llp_owner`,
   `incorporation_no`, `gst`, `pan`, the registered-address fields,
   the two SPOC name/phone pairs, `updated_at`, `last_synced_at`.
2. **`projects` upsert** (operational record). Looked up by `llp_id`
   (one LLP can later own multiple projects; the default project is
   "the one created by the webhook"). On first sync the project row
   reuses the LLP's UUID as its own `id`, preserving the 1:1 backfill
   mapping from migration 009. Columns written: `name`, `tier`,
   `status` (= LLP_Status), `city/state/pincode/country` (from the
   LLP's address), `total_units`, `units_issued`, `units_available`,
   `price_per_unit`, `total_project_cost`, `total_ticket_size`,
   `acreage_acres`, `annual_yield_pct`, `launch_year`, insurance
   fields, `updated_at`, `last_synced_at`.

**Coercions applied.**

- `asNumber(v)` — Deluge emits `""` for unset numerics; Postgres
  rejects empty string with `invalid input syntax for type numeric`.
  `asNumber` converts `""`/`null`/`undefined` to `undefined`, which
  drops the field from the upsert so Postgres uses NULL/default.
- `asDate(v)` — same behaviour for empty-string dates.
- `parsePercent(d.Annual_Rental_Yield)` — strips `%` and parses
  numeric.
- `asLaunchYearDate(d.Launch_Year)` — Zoho's `Launch_Year` is a
  year-only picklist (`"2026"`); the column is a `DATE`. Bare 4-digit
  strings are coerced to `YYYY-01-01`; full ISO dates pass through.

**CHECK constraints.** `projects` no longer has CHECK constraints on
`status` (migration 002 superseded migration 001 to remove the
`pending|operational|completed` enum so it can carry CRM's
`LLP_Status` strings verbatim).

**Flutter read.** `ProjectsRepository.myProjects()` first fetches the
investor's `investor_units.project_id` set via RLS, then runs
`client.from('projects').select().inFilter('id', ids)`. Marketplace
listings are read separately via
`client.from('projects').select().eq('is_listed_in_marketplace', true)`.
Exposed via `projectsProvider` and `marketplaceProjectsProvider`
(`lib/features/projects/projects_provider.dart`). Surfaces in: Home
(project progress cards), Projects list, Project detail, Explore
(marketplace).

The `llps` table is **not** read by Flutter directly — Project pages
treat the merged project row as the customer-facing record.

---

### 2.3 LLP_UnitAllocation_Module → `investor_units` (+ payouts, notifications)

**Trigger.** Zoho workflow rule on the LLP_UnitAllocation_Module fires
on create, on edit of any financial field, and on UTR fan-fields being
populated (`UTR_1..UTR_10`, `Amount_1..10`, `Date_1..10`).

**Deluge function.** `Push_Allocation_To_Supabase`. The Customer and
LLP fields are lookup objects; Zoho ships them as `{id, name}` nested
under `Customer` and `LLP`.

**Handler.** `handleAllocation(supabase, d)`:

1. Resolves FKs:
   - `customerZohoId = d.Customer.id` → `investors` row by
     `zoho_contact_id`.
   - `llpZohoId = d.LLP.id` → `llps` row, then the default project
     under that LLP.
   - Each missing FK throws (the webhook logs `failed` and surfaces in
     `webhook_log`).
2. Upserts the `investor_units` row keyed on `zoho_allocation_id`.
3. Unpacks the 1..10 UTR fan-fields. Each `(UTR_i, Amount_i, Date_i)`
   triple with a non-empty UTR and a numeric amount becomes one row in
   `payouts` with `source = 'crm'`, `status = 'processed'`, and
   `idempotency_key = ${zohoAllocationId}_payout_${i}`. The
   `idempotency_key` UNIQUE constraint plus `ignoreDuplicates: true`
   makes re-delivery safe.
4. If at least one payout was written, inserts a `notifications` row
   (`type = 'payout'`, body referencing the project name). Notification
   failure logs but does not roll back the financial writes.

**Coercions applied.** Same `asNumber`, `asDate`, `parsePercent` set
used by `handleProject`. `allocation_status` and `customer_status` are
passed through as free-text — no CHECK constraint.

**Flutter read.**

- Per-project allocation: `ProjectsRepository.myUnitsForProject(id)` →
  `investorAllocationProvider(projectId)` family.
- All allocations: `ProjectsRepository.myAllUnits()` →
  `investorUnitsListProvider`.
- Payouts list: `FinancialsRepository.myPayouts({projectId})` →
  `payoutsProvider`. Joins `projects(name)` so payout rows render the
  project name without a second round trip.
- Portfolio aggregates: `client.from('portfolio_summary').select()`
  via `FinancialsRepository.portfolioSummary` →
  `portfolioSummaryProvider`. `portfolio_summary` is a view (migration
  008) that sums `investor_units` and processed `payouts` per
  investor.

Surfaces in: Home (Portfolio card, Quick Stats, Project Progress),
Financials (Capital Account, Earnings Outlook, Payouts ledger),
Projects detail, Activity (the `notifications` insert from
`handleAllocation`).

---

## 3. The user lifecycle

End-to-end, from "ARL onboards an investor in Zoho" to "investor sees
their data in the APK".

1. **ARL staff creates a Zoho Contact** with the investor's name,
   email, mailing address, etc. The Contact gets a Zoho-internal
   record ID.
2. **ARL staff (or an automation) calls the `onboard-investor` Edge
   Function** with `X-ARL-Admin-Secret` and a body of
   `{email, name, arl_id, zoho_contact_id?, phone?, salutation?}`.
3. `onboard-investor` (`supabase/functions/onboard-investor/index.ts`)
   does three things:
   a. Calls `supabase.auth.admin.inviteUserByEmail(email, {data:
      {arl_id, name}, redirectTo: 'com.arl.app://auth'})`. This
      creates the `auth.users` row and triggers Supabase's invite
      email (Postgres role `supabase_auth_admin`, template configured
      in the Supabase dashboard).
   b. Inserts the matching `investors` row with `id =
      invited.user.id` (PK is `REFERENCES auth.users(id) ON DELETE
      CASCADE`), seeding `kyc_status = 'pending'` and
      `onboarded_at = NOW()`.
   c. If the `investors` insert fails it best-effort deletes the
      `auth.users` row so the email isn't blocked on retry.
4. **The investor receives a magic-link email** from Supabase Auth.
   Opening the link on Android hits `com.arl.app://auth` (registered
   in `AndroidManifest.xml` and `supabase/config.toml`
   `additional_redirect_urls`). The Flutter app catches the deep link
   and lands on the "set password" flow.
5. **Investor sets a password and signs in** via the Login screen
   (`lib/features/auth/login_screen.dart`). Supabase issues a JWT.
6. **First app open after sign-in:**
   - `authStateProvider` emits `INITIAL_SESSION`.
   - `currentInvestorProvider` runs `select() from investors
     limit 1`; RLS narrows to the row whose `id = auth.uid()`.
   - `projectsProvider` reads the user's `investor_units` to discover
     project IDs, then fetches the matching `projects`.
   - `portfolioSummaryProvider` reads the `portfolio_summary` view.
7. **Subsequent Zoho edits propagate live.** Any change to that
   investor's Contact / LLP / Allocation in Zoho fires the workflow,
   the webhook updates Supabase in ~2s, and the next Riverpod refresh
   in the app shows the new values. Offline cache (Hive,
   `ResilientCache`) holds the last successful response so the UI
   never blanks out on connectivity drops.

---

## 4. The two reconciliation paths

### 4.1 Webhook (real-time, push)

- **Endpoint.** `POST /functions/v1/zoho-crm-webhook`
  (deployed with `--no-verify-jwt`; configured in
  `[functions.zoho-crm-webhook]` in `supabase/config.toml`).
- **Auth.** `X-ARL-Webhook-Secret` header compared in constant time
  against the `WEBHOOK_SECRET` env var.
- **Idempotency.** `idempotency_key =
  ${module}_${recordId}_${modifiedTime}` is the UNIQUE column on
  `webhook_log`. A second delivery with the same key short-circuits
  and returns `{status: "duplicate"}`.
- **Audit.** Every request is logged to `webhook_log` with the body
  sanitised by `sanitizeForLogging()` so raw PAN / bank account /
  Aadhaar never enter the 90-day log retention window.
- **Latency.** ~2 seconds (Zoho workflow execution + HTTPS + Postgres
  upsert).
- **Failure mode.** On handler exception the `webhook_log` row is
  marked `status = 'failed'`, `error_message` is filled in, the
  exception is captured to Sentry if `SENTRY_EDGE_DSN` is set, and the
  HTTP 500 is returned to Zoho (which then triggers Zoho-side retry).

### 4.2 Reconcile cron (daily, pull)

- **Schedule.** Migration 024 schedules `zoho-reconcile-daily` at
  `'0 1 * * *'` — **01:00 UTC**, daily (06:30 IST). (The task brief
  said 00:30 UTC; the migration is the truth.)
- **Auth.** `x-arl-cron-secret` header against `CRON_SECRET`. The cron
  itself fetches the secret from `vault.decrypted_secrets` and posts
  it in the header.
- **Algorithm** (`supabase/functions/zoho-reconcile-daily/index.ts`):
  1. Refresh a Zoho access token via `ZOHO_REFRESH_TOKEN`,
     `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET` against
     `https://accounts.zoho.in/oauth/v2/token`.
  2. For each of `Contacts`, `LLP_Creation_Module`,
     `LLP_UnitAllocation_Module`: compute
     `since = greatest(NOW() - 25h, max(last_synced_at) - 1h)`,
     page through the Zoho v3 list endpoint with `If-Modified-Since:
     since`, applying the same field map the webhook uses (and the
     same `asNumber` / `asDate` / `mapKycStatus` / `asLaunchYearDate`
     coercions).
  3. Honour `Modified_Time` so a stale CRM record never overwrites a
     newer Supabase row.
  4. Refresh `last_synced_at` on every row visited (even when no
     fields changed) so freshness checks reflect the pass.
- **Latency.** Up to 24 hours. Acts as the safety net for missed
  webhooks (workflow disabled, secret mismatch, retry exhausted,
  network partition during the push).
- **Result.** Writes a `webhook_log` audit row with
  `event_type = 'reconcile_daily'` summarising `{contacts: {scanned,
  updated}, llps: {…}, allocs: {…}}`.
- **Sync-staleness alerting.** `sync-stale-alert` runs hourly
  (migration 024). It reads the `sync_status` view (per-table
  `max(last_synced_at)`) and inserts a `sync_alerts` row if the age
  exceeds the per-table threshold: `llps` and `projects` 24h,
  `investors` 6h, `investor_units` 2h.

### 4.3 What the cron does NOT do

- It does **not** propagate Zoho soft-deletes (neither does the
  webhook). Deletes have to be handled out-of-band.
- It does **not** create new investor rows. If a Contact exists in
  Zoho but no `investors` row, both push and pull paths skip the
  record silently — `onboard-investor` must run first.
- The booleans on Contacts are **not** included in `CONTACT_FIELDS`
  because Deluge serialises them as strings and the webhook handler
  treats anything that isn't strictly `=== true` as `false`. Round-
  tripping them via reconcile would silently flip every flag to
  `false`.

---

## 5. Field reference tables

Columns and types are as they exist in current production (`llps`
columns inferred from the webhook + reconcile handlers; the explicit
`CREATE TABLE public.llps` was applied directly to the DB and is not
in the in-repo migration set — see Section 8 follow-up).

### 5.1 `public.investors`

| Column | Type | Source | Coercion | Notes |
|---|---|---|---|---|
| `id` | `UUID PK` | `auth.users.id` | — | `REFERENCES auth.users(id) ON DELETE CASCADE`. Set by `onboard-investor`. |
| `zoho_contact_id` | `TEXT` | `Contacts.id` | — | UNIQUE in migration 002 (but see §8 — superseded col is nullable). Webhook FK key. |
| `arl_id` | `TEXT UNIQUE NOT NULL` | computed by ARL staff | — | e.g. `ARL-00142`. Passed in `onboard-investor` body. |
| `name` | `TEXT NOT NULL` | `First_Name + Last_Name` (or `Full_Name`) | trim + join | Falls back to `(unknown)`. |
| `email` | `TEXT UNIQUE NOT NULL` | `Email` | — | |
| `phone` | `TEXT` | `Mobile ?? Phone` | — | |
| `salutation` | `TEXT` | `Salutation` | — | |
| `kyc_status` | `TEXT NOT NULL CHECK (…)` | `KYC` | `mapKycStatus` | Enum: `pending\|in_progress\|verified\|rejected`. |
| `pan_masked` | `TEXT` | `PAN_Number` | `maskPan` | `RTYUI****L`. Raw PAN never stored. |
| `bank_account_masked` | `TEXT` | `Bank_Account_Number` | `maskBankAccount` | `XXXX-XXXX-9012`. |
| `bank_ifsc` | `TEXT` | `ISFC_Code` | — | (Note Zoho typo: `ISFC` not `IFSC`.) |
| `bank_branch` | `TEXT` | `Bank_Branch` | — | |
| `bank_holder_name` | `TEXT` | `Account_Holder_Full_name` | — | |
| `bank_name` | `TEXT` | `Bank_Name` | — | |
| `address_line1` | `TEXT` | `Mailing_Street` | — | |
| `city` | `TEXT` | `Mailing_City` | — | |
| `state` | `TEXT` | `Mailing_State` | — | |
| `pincode` | `TEXT` | `Mailing_Zip` | — | |
| `country` | `TEXT` | `Mailing_Country` | — | |
| `unit_allocated` | `BOOLEAN` | `Unit_allocated` | `=== true` | Strict equality — string `"true"` becomes `false`. |
| `payment_received` | `BOOLEAN` | `Payment_received` | `=== true` | |
| `profile_verified` | `BOOLEAN` | `Profile_verified` | `=== true` | |
| `agreement_signed` | `BOOLEAN` | `Agreement_signed` | `=== true` | |
| `fema_applicable` | `BOOLEAN` | `FEMA_Applicable` | `=== true` | |
| `onboarded_at` | `TIMESTAMPTZ` | `NOW()` at insert | — | Set by `onboard-investor`. |
| `updated_at` | `TIMESTAMPTZ` | `Modified_Time` | `incomingUpdated.toISOString()` | Stale-write guard compares this. |
| `last_synced_at` | `TIMESTAMPTZ` | `NOW()` at write | — | Added in migration 023; populated on every webhook + reconcile write. |

### 5.2 `public.llps`

| Column | Type | Source | Coercion | Notes |
|---|---|---|---|---|
| `id` | `UUID PK` | `gen_random_uuid()` | — | Project `id` is set equal to this on first sync. |
| `zoho_llp_id` | `TEXT UNIQUE` | `LLP_Creation_Module.id` | — | Upsert key. |
| `name` | `TEXT` | `Name` | — | |
| `llp_status` | `TEXT` | `LLP_Status` | — | Free-text; mirrored to `projects.status`. |
| `llp_owner` | `TEXT` | `LLP_Owner` | — | |
| `incorporation_no` | `TEXT` | `Incorporation_No` | — | |
| `gst` | `TEXT` | `GST` | — | |
| `pan` | `TEXT` | `PAN` | — | Entity PAN — fine to store unmasked. |
| `registered_address_line1` | `TEXT` | `Address_Line_1` | — | |
| `registered_city` | `TEXT` | `Address_Line_1_City` | — | |
| `registered_state` | `TEXT` | `Address_Line_1_State_Province` | — | |
| `registered_pincode` | `TEXT` | `Address_Line_1_Zip_Postal_Code` | — | |
| `registered_country` | `TEXT` | `Address_Line_1_Country_Region` | — | |
| `spoc1_name` / `spoc1_phone` | `TEXT` | `SPOC_1_Full_Name` / `SPOC_1_Contact_No` | — | |
| `spoc2_name` / `spoc2_phone` | `TEXT` | `SPOC_2_Full_Name` / `SPOC_2_Contact_No` | — | |
| `updated_at` | `TIMESTAMPTZ` | `NOW()` at write | — | |
| `last_synced_at` | `TIMESTAMPTZ` | `NOW()` at write | — | |

### 5.3 `public.projects`

| Column | Type | Source | Coercion | Notes |
|---|---|---|---|---|
| `id` | `UUID PK` | first sync uses `llp_id`; later projects use `gen_random_uuid()` | — | |
| `llp_id` | `UUID REFERENCES llps(id)` | resolved by `handleProject` | — | One LLP can own multiple projects; the webhook only updates the *default* project. |
| `name` | `TEXT NOT NULL` | `Name` | — | |
| `tier` | `TEXT` | `Tier` | — | e.g. `10 L`. Surfaced in app as "crop type" string. |
| `status` | `TEXT` | `LLP_Status` | — | No CHECK constraint in current schema. |
| `city/state/pincode/country` | `TEXT` | LLP's `Address_Line_1_*` | — | Project location displayed in app. |
| `total_units` | `INT` | `Total_Units` | `asNumber` | |
| `units_issued` | `INT` | `Units_Issued` | `asNumber` | |
| `units_available` | `INT` | `Units_Available_to_Issue` | `asNumber` | |
| `price_per_unit` | `NUMERIC(14,2)` | `Pet_Unit_Price` | `asNumber` | Field name is `Pet_Unit_Price` in CRM (typo upstream). |
| `total_project_cost` | `NUMERIC(14,2)` | `Total_Project_Cost` | `asNumber` | |
| `total_ticket_size` | `NUMERIC(14,2)` | `Total_Ticket_Size` | `asNumber` | Powers "Total invested" on the project card. |
| `acreage_acres` | `NUMERIC(10,2)` | `Acreage_Acres` | `asNumber` | |
| `annual_yield_pct` | `NUMERIC(5,2)` | `Annual_Rental_Yield` | `parsePercent` | Strips `%`. |
| `launch_year` | `DATE` | `Launch_Year` | `asLaunchYearDate` | Year picklist → `YYYY-01-01`. |
| `insurance_provider` | `TEXT` | `Insurance_Provider` | — | |
| `insurance_policy_no` | `TEXT` | `Insurance_Policy_No` | — | |
| `insurance_expiry_date` | `DATE` | `Insurance_expiry_date` | `asDate` | |
| `insured_amount` | `NUMERIC(14,2)` | `Insured_Amount` | `asNumber` | |
| `cover_image_path` | `TEXT` | manual (Storage path) | — | Hero image (Supabase Storage). |
| `color_hex` / `accent_hex` | `TEXT` | manual | — | Per-project theming. |
| `is_listed_in_marketplace` | `BOOLEAN` (added later) | manual | — | Toggle to surface on the Explore tab; admin edits in Studio. |
| `updated_at` | `TIMESTAMPTZ` | `NOW()` at write | — | |
| `last_synced_at` | `TIMESTAMPTZ` | `NOW()` at write | — | |

### 5.4 `public.investor_units`

| Column | Type | Source | Coercion | Notes |
|---|---|---|---|---|
| `id` | `UUID PK` | `gen_random_uuid()` | — | |
| `zoho_allocation_id` | `TEXT UNIQUE` | `LLP_UnitAllocation_Module.id` | — | Upsert key. |
| `investor_id` | `UUID FK → investors(id)` | resolved by `Customer.id` → `zoho_contact_id` | — | `ON DELETE CASCADE`. |
| `project_id` | `UUID FK → projects(id)` | resolved by `LLP.id` → `llps.id` → default project | — | `ON DELETE CASCADE`. |
| `issued_units` | `INT NOT NULL DEFAULT 0` | `Issued_Units` | `asNumber` (webhook), pass-through (reconcile) | |
| `reserved_units` | `INT NOT NULL DEFAULT 0` | `Reserved_Units` | `asNumber` | |
| `unit_price` | `NUMERIC(14,2)` | `Unit_Price` | `asNumber` | |
| `capital_invested` | `NUMERIC(14,2)` | `Capital_Invested` | `asNumber` | |
| `capital_outstanding` | `NUMERIC(14,2)` | `Capital_Outstanding` | `asNumber` | |
| `capital_returns` | `NUMERIC(14,2)` | `Capital_Returns` | `asNumber` | |
| `total_amount_receivable` | `NUMERIC(14,2)` | `Total_Amount_Receivable` | `asNumber` | |
| `total_amount_received` | `NUMERIC(14,2)` | `Total_Amount_Received` | `asNumber` | |
| `token_advance_amount` | `NUMERIC(14,2)` | `Token_Advance_Amount` | `asNumber` | |
| `annual_yield_pct` | `NUMERIC(5,2)` | `Annual_Rental_Yield` | `parsePercent` | |
| `allocation_status` | `TEXT` | `Allocation_Status` | — | Free-text. |
| `customer_status` | `TEXT` | `Customer_Status` | — | Free-text. |
| `investment_date` | `DATE` | `Investment_Date` | `asDate` (webhook) | |
| `next_payout_date` | `DATE` | `Next_Payout` | `asDate` (webhook) | |
| `updated_at` | `TIMESTAMPTZ` | `NOW()` at reconcile write only | — | (Webhook does not set this on `investor_units` — see §8.) |
| `last_synced_at` | `TIMESTAMPTZ` | `NOW()` at every write | — | |

`payouts` is derived from the same record: each `(UTR_i, Amount_i,
Date_i)` triple becomes one row with
`idempotency_key = ${zoho_allocation_id}_payout_${i}` and
`source = 'crm'`.

---

## 6. Secrets and configuration

| Name | Where it lives | Used by | Purpose |
|---|---|---|---|
| `SUPABASE_URL` | Supabase Functions env (auto-injected) + Flutter `.env` | All Edge Functions, Flutter `SupabaseConstants.url` | API base URL. |
| `SUPABASE_ANON_KEY` | Supabase Functions env + Flutter `.env` | `_shared/supabase.ts userClient`, Flutter `SupabaseConstants.anonKey` | Public client key (RLS-scoped). |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Functions env (auto-injected, never in `.env`) | All Edge Functions (admin client) | Bypasses RLS for server-side writes. |
| `WEBHOOK_SECRET` | `supabase secrets set` | `zoho-crm-webhook` | Validates `X-ARL-Webhook-Secret` from Zoho Deluge POSTs (constant-time compare). |
| `ADMIN_SECRET` | `supabase secrets set` | `onboard-investor` | Validates `X-ARL-Admin-Secret` from ARL staff onboarding calls. |
| `CRON_SECRET` | `supabase secrets set` + Postgres Vault entry `cron_secret` | `zoho-reconcile-daily`, `sync-stale-alert`, `gallery-sync`, `health-check` | pg_cron jobs read the Vault entry and post it as `x-arl-cron-secret`. |
| `ZOHO_CLIENT_ID` | `supabase secrets set` | `zoho-reconcile-daily` | OAuth client for the Zoho REST API. |
| `ZOHO_CLIENT_SECRET` | `supabase secrets set` | `zoho-reconcile-daily` | |
| `ZOHO_REFRESH_TOKEN` | `supabase secrets set` | `zoho-reconcile-daily` | Long-lived refresh token; access tokens are minted per run via `https://accounts.zoho.in/oauth/v2/token`. |
| `SENTRY_EDGE_DSN` | `supabase secrets set` (optional) | `zoho-crm-webhook`, `zoho-reconcile-daily`, `onboard-investor` | Exception capture. |
| `ARL_APP_MODE` | Flutter `.env` (`live` / `demo`) | `SupabaseConstants.isDemoMode` | `demo` skips all network calls; UI runs against `core/mock/demo_data.dart`. |
| `ARL_DEV_BYPASS` | Flutter `.env` (debug builds only) | `SupabaseConstants.devBypassAuth` | Treats the router as signed-in even with no Supabase session. `kReleaseMode` forces it to `false`. |

**Function deploy auth posture** (`supabase/config.toml`):
- `zoho-crm-webhook`, `zoho-reconcile-daily`, `sync-stale-alert`:
  `verify_jwt = false` — shared-secret only.
- `onboard-investor`, `create-ticket`, `reply-ticket`,
  `bank-change-request`: CLI default `verify_jwt = true` (admin
  secret or investor JWT enforced at handler level).

The deep-link `com.arl.app://auth` is registered both in
`AndroidManifest.xml` and `[auth] additional_redirect_urls`.

---

## 7. Where each user-visible thing comes from

### Home (`lib/features/home/home_screen.dart`)

- **Welcome name** — `portfolioSummaryProvider` → fallback chain:
  `investors.name` → `user_metadata.name` → email local-part →
  literal `'Investor'`.
- **Project selector pill** — `selectedProjectIdProvider`.
- **Portfolio card** (Total Portfolio Value, Invested, Returns) —
  `scopedPortfolioProvider` reading the `portfolio_summary` view, or
  the single selected `investor_units` row if a project is picked.
- **Quick stats row** (Active Units, ROI %, Avg Yield, Next Payout) —
  same provider.
- **Project progress cards** — `projectsProvider` (joined with
  per-project `project_phases` for the progress bar) and
  `investorUnitsListProvider` for "units owned".

### Projects (`lib/features/projects/projects_list_screen.dart`,
`project_detail_screen.dart`)

- **List** — `projectsProvider` → `projects` rows filtered by RLS
  through the user's `investor_units`.
- **Detail header** — `projectByIdProvider(id)`.
- **Phases timeline** — `projectPhasesProvider(projectId)` →
  `project_phases` rows (manually seeded by ARL staff; no Zoho
  source).
- **My allocation block** — `investorAllocationProvider(projectId)` →
  the `investor_units` row.

### Financials (`lib/features/financials/financials_screen.dart`)

- **Capital Account / Earnings Outlook** — `scopedPortfolioProvider`.
- **Payouts ledger tab** — `payoutsProvider` → `payouts` rows joined
  with `projects(name)`, scoped to the selected project if any.

### Explore (`lib/features/explore/explore_screen.dart`)

- **Marketplace cards** — `marketplaceProjectsProvider` →
  `projects` rows where `is_listed_in_marketplace = true`. Sorted by
  `marketplace_sort_order` if present.
- **Investment calculator** — local UI state plus the selected
  project's `price_per_unit` and `annual_yield_pct`.

### Activity / Notifications (`lib/features/activity/activity_screen.dart`)

- **Feed** — `notificationsProvider` → `notifications` rows for the
  signed-in investor (RLS-filtered, newest first, limit 50).
- **Unread badge** — `unreadCountProvider` → exact `count` of rows
  with `read_at IS NULL`.
- Source: webhook insert in `handleAllocation` (`type='payout'`),
  `gallery-sync` cron (`type='photo'`), `reply-ticket` Edge Function
  (`type='ticket'`).

### Profile (`lib/features/profile/profile_screen.dart`,
`kyc_screen.dart`, `bank_details_screen.dart`)

- **Profile header** — `currentInvestorProvider` →
  `investors.{name, arl_id, kyc_status}` plus `projects.length` for
  the projects count.
- **KYC screen** — `investors.{pan_masked, kyc_status, aadhaar_masked,
  date_of_birth, address fields}` from the same provider.
- **Bank details** — `investors.{bank_name, bank_account_masked,
  bank_ifsc, bank_holder_name, bank_branch}`. Edit flow posts to
  the `bank-change-request` Edge Function (human-in-the-loop;
  resolved by ARL staff updating Zoho, then the webhook syncs back).

### Documents (`lib/features/documents/documents_screen.dart`)

- `documents` rows for the signed-in investor, joined with project
  name where present. Files served via Supabase Storage signed URLs
  (1-hour expiry).

### Gallery (`lib/features/gallery/gallery_screen.dart`)

- `gallery_photos` rows scoped by RLS via `investor_units.project_id`.
  Rows seeded by the `gallery-sync` Edge Function (separate daily
  cron) which polls LLP_Creation_Module attachments.

### Support (`lib/features/support/`)

- `support_tickets` and `ticket_messages` are Supabase-native (no
  Zoho source). Investor inserts go through `create-ticket` /
  `reply-ticket` Edge Functions; staff reply by writing
  `ticket_messages` directly in Supabase Studio.

---

## 8. Open questions, known limitations, and follow-ups

These are real issues in the code as of this commit — not
documentation guesses.

1. **`handleContact` is silent-skip on no-row.** If the Zoho Contact
   webhook fires before `onboard-investor` has run, no `investors`
   row exists and the handler returns without logging. The reconcile
   cron behaves the same way. **Mitigation:** always call
   `onboard-investor` *before* enabling the Contacts workflow rule on
   a brand-new investor. **Follow-up:** consider inserting a "pending
   onboarding" sentinel row, or at least logging the skip to
   `webhook_log` with `status='failed'`.

2. **`zoho_contact_id` is nullable.** Migration 002 declares it
   UNIQUE but nullable, and `onboard-investor` will insert with
   `zoho_contact_id: null` if the caller omits it. Two investors with
   no CRM linkage will both have NULL there (multiple NULLs are
   allowed under a UNIQUE constraint in Postgres), creating a
   duplicate-investor risk where the same Contact gets created twice
   before being linked. **Follow-up:** require `zoho_contact_id` in
   the `onboard-investor` body, or add a partial UNIQUE index that
   excludes NULL.

3. **Boolean fields in the Contacts sync require strict JSON `true`.**
   `handleContact` writes `unit_allocated: d.Unit_allocated === true`
   (and the other four flags). Deluge sometimes emits booleans as the
   strings `"true"`/`"false"`; those collapse to `false` silently.
   When a new boolean is added to Contacts, the Deluge function must
   ship a JSON literal `true`/`false`, not a string. This is why
   `CONTACT_FIELDS` in `zoho-reconcile-daily` deliberately excludes
   the booleans.

4. **`LLP_FIELDS` in reconcile must stay aligned with
   `Push_LLP_To_Supabase`.** Both ends list the same Zoho field
   names; if either side adds a field without the other, the next
   reconcile pass will overwrite real CRM values with empty defaults.
   Same caution applies to `CONTACT_FIELDS` and `ALLOCATION_FIELDS`.
   **Follow-up:** generate the field lists from a shared source of
   truth, or add a UAT step that diffs the two.

5. **Daily reconcile uses Zoho REST v3 directly.** Access tokens are
   minted per run from `ZOHO_REFRESH_TOKEN` against the IN data
   centre (`accounts.zoho.in`, `zohoapis.in`). If the org moves to
   another DC (`.com`, `.eu`), both base URLs must change.

6. **Schedule mismatch.** The task brief described the cron as
   "daily, 00:30 UTC"; the actual migration (024) schedules it at
   `0 1 * * *` = 01:00 UTC (06:30 IST). The text of this guide
   follows the migration.

7. **`llps` is not in the in-repo migration set.** Migration 002
   creates `projects` with LLP-style columns; later refactoring split
   the LLP metadata into a separate `llps` table that the webhook +
   reconcile read/write, but the `CREATE TABLE public.llps …`
   statement was applied directly to the database (migration 023
   already `ALTER`s it to add `last_synced_at`). **Follow-up:** add a
   migration that codifies the `llps` schema so a fresh `db push`
   from this repo reproduces production. The columns currently in
   use are listed in Section 5.2.

8. **Migration 001 and 002 disagree.** 001 defined `investors` with
   `address_json`, `aadhaar_masked`, and a 3-state
   `kyc_status` CHECK (`pending|verified|rejected`). 002 redefines
   the table with split address columns, no `aadhaar_masked`, and a
   4-state CHECK adding `in_progress`. Today's writes go through 002.
   `aadhaar_masked` is still referenced by the Flutter KYC screen
   (`lib/features/profile/kyc_screen.dart`) — it reads from a column
   that is no longer written by the sync pipeline, so it always
   renders `—`. **Follow-up:** either re-add the column + write path,
   or drop the field from the KYC screen.

9. **`updated_at` on `investor_units` is not set by the webhook.**
   `handleAllocation` in `zoho-crm-webhook` writes `last_synced_at`
   but does not set `updated_at`. The reconcile cron does set both.
   That makes `updated_at` lag behind reality on webhook-only paths;
   downstream consumers that rely on it (none today) would see
   surprising staleness. The trigger from migration
   `010_updated_at_triggers.sql` may already paper over this — verify
   before relying on it.

10. **Soft-deletes are not propagated.** Neither the webhook nor the
    reconcile cron handles Zoho deletes. A deleted CRM record stays
    in Supabase until manually removed. Track separately.

11. **Programmatic Zoho creates skip workflow rules by default.**
    `createRecords` and `updateRecord` API calls (and MCP equivalents)
    do **not** fire workflow rules — including our "Supabase Sync"
    rules — unless the body explicitly sets `trigger: ["workflow"]`.
    A CRM record created via Postman / Deluge / MCP without that flag
    will not appear in Supabase via the push webhook. The
    `zoho-reconcile-daily` cron (01:00 UTC) is the safety net: it
    pulls every record with `Modified_Time` in the look-back window
    and upserts via the same handler code path the webhook uses. Cron
    lag is the worst-case latency for programmatic creates that omit
    the trigger flag. UI creates always fire workflow rules and
    propagate within seconds (DEF-2026-05-11-03).

12. **`LLP_UnitAllocation_Module.Name` is mandatory on API creates.**
    Zoho's UI auto-generates the field via auto-number; programmatic
    callers must supply it explicitly. Use `UAT-<YYYY-MM-DD>-<n>` for
    fixtures or `<arl_id>-<short_llp>-<seq>` for production. The
    webhook handler ignores `Name` — it's purely a Zoho display value
    (DEF-2026-05-11-04).

13. **`investors.zoho_contact_id` is partially UNIQUE.** Migration 025
    adds `investors_zoho_contact_id_unique` — a partial UNIQUE index
    on the column where NOT NULL. Prevents two `investors` rows from
    linking to the same Zoho Contact. Multiple NULL values are still
    allowed for manual / unlinked test rows. Violations surface as
    Postgres `23505` from `onboard-investor` (DEF-2026-05-11-05).
