# Growize App — Test Scenarios & Fixture Spec

**Version:** 2.0 (rewritten under demo-suffix rule)
**Created:** 2026-05-05
**Companion to:** `TEST_PLAN.md`, `DAILY_UAT_RUNBOOK.md`, `ARL_Test_Tracker.xlsx`

---

## How to read this document

- **§1 — Demo-suffix rule.** Repeated here for emphasis.
- **§2 — Fixture spec.** What `-demo` records need to exist in CRM. You create them in CRM; we never edit them as part of testing.
- **§3 — Scenarios & cases.** Each scenario assumes its required fixtures already exist. Steps verify Supabase + app — never write to CRM.
- **§4 — Negative / edge cases.**

---

## §1. Demo-suffix rule

Every test fixture record's name **MUST end with `-demo`**. The suffix is the canonical filter that separates production from test data. Examples:

- LLP: `Alpha Agro LLP-demo`
- Project: `Mango Orchard-demo`
- Investor: `Aarav Sharma-demo`, email `aarav-demo@arl.test`
- Allocation: anything that points at the above

Production builds of the app must filter `-demo` records out of any non-demo investor's view.

---

## §2. Fixture spec — what we need in CRM

This is a **requirements list**, not a creation list for tests. ARL Tech (or assigned admin) creates these `-demo` records in Zoho CRM **once**, before the test cycle begins. After that, tests only observe and verify; they do not edit.

When a fixture is created, fill its **CRM ID** in the corresponding row of the `Fixture Spec` sheet of `ARL_Test_Tracker.xlsx`. That sheet is the bridge between "what the test expects" and "the actual record in CRM".

### F-LLP — LLPs

| Fixture key | Required attributes | Used by |
|---|---|---|
| F-LLP-A | Active LLP with at least 2 child projects, 1 of which is Active and 1 Not Started | SC-LLP, SC-PRJ, SC-ALC-001/002/003/004 |
| F-LLP-B | Active LLP with exactly 1 active project, single allocated investor | SC-ALC-005 |
| F-LLP-C | Active LLP with zero projects | SC-LLP-002 (empty state) |

### F-PRJ — Projects

| Fixture key | Required attributes | Used by |
|---|---|---|
| F-PRJ-A1 | Belongs to F-LLP-A. Status = Active. Total units, unit value populated. | SC-ALC-001, SC-ALC-003, SC-ALC-004 |
| F-PRJ-A2 | Belongs to F-LLP-A. Status = Not Started. | SC-ALC-002, SC-PRJ-002 |
| F-PRJ-B1 | Belongs to F-LLP-B. Status = Active. | SC-ALC-005 |
| F-PRJ-EXIT | Any LLP. Status = Exit/Closed. Has payout fields populated for at least one allocation. | SC-EXIT-001 |

### F-INV — Investors

Each investor must have a working email so we can issue an OTP/login token.

| Fixture key | Required attributes | Used by |
|---|---|---|
| F-INV-01 | Onboarded. One Paid + Active allocation only. | SC-ALC-001 |
| F-INV-02 | Onboarded. One Paid + Not Started allocation only. | SC-ALC-002 |
| F-INV-03 | Onboarded. One Pending payment allocation. | SC-ALC-003 |
| F-INV-04 | Onboarded. One Partial payment allocation (50% paid). | SC-ALC-004 |
| F-INV-05 | Onboarded. Allocations to two different projects across two LLPs (multi-project). | SC-ALC-005 |
| F-INV-06 | Onboarded but ZERO allocations. | SC-NEG-005 |
| F-INV-07 | Two CRM records share the same email (negative). | SC-NEG-002 |

### F-ALC — Allocations

| Fixture key | Investor | Project | State | Used by |
|---|---|---|---|---|
| F-ALC-01 | F-INV-01 | F-PRJ-A1 | Paid + Active | SC-ALC-001 |
| F-ALC-02 | F-INV-02 | F-PRJ-A2 | Paid + Not Started | SC-ALC-002 |
| F-ALC-03 | F-INV-03 | F-PRJ-A1 | Pending (paid = 0) | SC-ALC-003 |
| F-ALC-04 | F-INV-04 | F-PRJ-A1 | Partial (paid = 50% of committed) | SC-ALC-004 |
| F-ALC-05 | F-INV-05 | F-PRJ-A1 | Paid + Active | SC-ALC-005 |
| F-ALC-06 | F-INV-05 | F-PRJ-B1 | Paid + Active | SC-ALC-005 |
| F-ALC-EXIT | F-INV-01 | F-PRJ-EXIT | Closed with payout | SC-EXIT-001 |

### F-DOC — Documents

| Fixture key | Required attributes | Used by |
|---|---|---|
| F-DOC-01 | One PDF doc scoped to F-INV-01 only | SC-DOC-001 |

---

## §3. Scenarios & cases

### Naming

- **Scenario ID:** `SC-<area>-###` (e.g., `SC-LLP-001`)
- **Test Case ID:** `TC-<area>-###-##`
- **Layer values:** `Sync`, `Supabase`, `App`, `Auth`, `RLS`, `Mixed`. (CRM is observation-only — no test ever writes to CRM.)

### Master flow — what we are validating

```
Zoho CRM (READ-ONLY)
  │  -demo records exist:
  │  – LLP-demo
  │  – Project-demo (lookup → LLP)
  │  – Lead-demo / Contact-demo (Investor)
  │  – Allocation-demo (LLP, Project, Investor, units, committed, paid, status)
  │
  ▼
Sync edge function
  │  Pulls -demo records into Supabase
  ▼
Supabase
  │  llps, projects, investors, investor_units, documents
  │  RLS scoped per investor + demo filter
  ▼
Flutter App (read-only)
  – Investor logs in
  – Sees their portfolio with correct payment + project state
```

---

### SC-LLP-001 — LLP visibility

**Goal:** A `-demo` LLP that exists in CRM is reflected in Supabase and visible (via projects) in the app.
**Required fixtures:** F-LLP-A.

| Case ID | Step (observe / verify only) | Expected | Layer |
|---|---|---|---|
| TC-LLP-001-01 | Confirm F-LLP-A `-demo` LLP exists in CRM (read-only). | Record visible with expected name, status. | Observe |
| TC-LLP-001-02 | Query Supabase `llps` for the F-LLP-A row. | Row exists; matches CRM name and status; FK to CRM ID. | Supabase |
| TC-LLP-001-03 | Login to app as F-INV-01 (allocated to a project under this LLP). | LLP-related project list renders. No errors. | App |
| TC-LLP-001-04 | Update CRM record's `last_modified` (e.g., admin edits a non-critical field outside testing). Wait sync window. | Supabase row reflects update; app shows updated value. | Sync → App |

### SC-LLP-002 — Empty LLP

**Required fixtures:** F-LLP-C.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-LLP-002-01 | Verify F-LLP-C row in Supabase has zero child projects. | `count(projects where llp_id = F-LLP-C) = 0`. | Supabase |
| TC-LLP-002-02 | Login as a test investor with admin/explore access. View the explore screen. | Empty state for that LLP rendered (no crash, no infinite loader). | App |

---

### SC-PRJ-001 — Project under LLP

**Required fixtures:** F-LLP-A, F-PRJ-A1.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-PRJ-001-01 | Verify F-PRJ-A1 in Supabase `projects`. | Row exists; FK to F-LLP-A; status Active; total_units, unit_value populated. | Supabase |
| TC-PRJ-001-02 | Login as F-INV-01. View portfolio. | F-PRJ-A1 visible with units (per F-ALC-01). | App |
| TC-PRJ-001-03 | Login as F-INV-06 (zero allocations). | F-PRJ-A1 NOT visible in portfolio. | RLS |

### SC-PRJ-002 — Project state transitions

**Required fixtures:** F-PRJ-A2.
This scenario *observes* a project changing state. Since we cannot write to CRM, the test runs when the operations team transitions the project legitimately (e.g., as part of a real launch event), or in a Supabase staging clone where we can simulate.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-PRJ-002-01 | After F-PRJ-A2 transitions Not Started → Active in CRM (and sync runs). | Supabase status flips to Active. | Sync |
| TC-PRJ-002-02 | App view for F-INV-02 (allocated to F-PRJ-A2). | Status badge changes to Active; earnings section appears. | App |
| TC-PRJ-002-03 | After F-PRJ-EXIT transitions Active → Exit in CRM. | App moves project to Exit tab; payout details shown. | App |

---

### SC-INV-001 — Investor lifecycle and login

**Required fixtures:** F-INV-01, F-INV-02.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-INV-001-01 | Verify F-INV-01 exists in Supabase `investors`. | Row exists; email matches. | Supabase |
| TC-INV-001-02 | Trigger app login (magic link / OTP) for F-INV-01's email. | Token delivered; auth user created or matched. | Auth |
| TC-INV-001-03 | Login as F-INV-01. | Lands on Home; portfolio renders. | App |
| TC-INV-001-04 | Logout. | Session cleared; login screen shown. | Auth |
| TC-INV-001-05 | Login as F-INV-02 immediately. | Sees F-INV-02 portfolio only — no F-INV-01 leak. | App / RLS |

---

### SC-ALC-001 — Paid + Project Active

**Required fixtures:** F-INV-01, F-PRJ-A1, F-ALC-01.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-ALC-001-01 | Verify F-ALC-01 in Supabase. | Row exists; payment_status=Paid; units, amounts, FKs correct. | Supabase |
| TC-ALC-001-02 | Login as F-INV-01; open Home / Portfolio. | F-PRJ-A1 listed with units = F-ALC-01 units; value = units × unit_value. | App |
| TC-ALC-001-03 | Open project detail. | Active status; units; payment Paid. | App |
| TC-ALC-001-04 | Open Financials. | Current value rendered; if returns posted, NAV/yield shown. | App |
| TC-ALC-001-05 | Login as a different investor (F-INV-02). | Does NOT see F-ALC-01 / F-INV-01 data. | RLS |

### SC-ALC-002 — Paid + Project Not Started

**Required fixtures:** F-INV-02, F-PRJ-A2, F-ALC-02.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-ALC-002-01 | Verify F-ALC-02 + F-PRJ-A2 in Supabase. | Allocation Paid; project status not_started. | Supabase |
| TC-ALC-002-02 | Login as F-INV-02. | Portfolio shows F-PRJ-A2 with units, payment Paid, badge Not Started. | App |
| TC-ALC-002-03 | Verify financials. | Current value = committed; no yield / earnings shown. | App |

### SC-ALC-003 — Payment Pending

**Required fixtures:** F-INV-03, F-PRJ-A1, F-ALC-03.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-ALC-003-01 | Verify F-ALC-03 in Supabase. | payment_status=Pending; paid_amount=0. | Supabase |
| TC-ALC-003-02 | Login as F-INV-03. | F-PRJ-A1 visible with units committed; "Payment Pending" banner; no value/earnings. | App |
| TC-ALC-003-03 | Open project detail. | Clear call-out: pay X to activate; instructions / contact link. | App |

### SC-ALC-004 — Partial Payment

**Required fixtures:** F-INV-04, F-PRJ-A1, F-ALC-04.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-ALC-004-01 | Verify F-ALC-04 in Supabase. | paid = 50% of committed; status Partial; derived percent computed. | Supabase |
| TC-ALC-004-02 | Login as F-INV-04. | Portfolio shows committed units, partial state, outstanding balance. | App |
| TC-ALC-004-03 | Confirm display rule (full units vs proportional active) matches product spec. | Matches spec; otherwise file defect. | App |

### SC-ALC-005 — Multi-project investor

**Required fixtures:** F-INV-05, F-PRJ-A1, F-PRJ-B1, F-ALC-05, F-ALC-06.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-ALC-005-01 | Verify both allocations in Supabase. | Both rows present; FKs correct. | Supabase |
| TC-ALC-005-02 | Login as F-INV-05. | Portfolio lists both projects (across two LLPs). | App |
| TC-ALC-005-03 | Verify dashboard totals. | total_units = sum across allocations; total_invested = sum committed. | App |
| TC-ALC-005-04 | Drill into each project detail. | Each detail page shows only that project's data. | App |

---

### SC-AUTH-001 — Authentication & isolation

**Required fixtures:** F-INV-01, F-INV-02.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-AUTH-001-01 | Login as F-INV-01 with valid OTP. | Login OK; portfolio renders. | Auth |
| TC-AUTH-001-02 | Enter wrong OTP. | Rejected with clear error; no session. | Auth |
| TC-AUTH-001-03 | Logout. | Session cleared. | Auth |
| TC-AUTH-001-04 | Login as F-INV-02 immediately. | Sees own data only; cache from F-INV-01 cleared. | App / Cache |
| TC-AUTH-001-05 | Try to access another investor's deep link. | Blocked / 403 / redirect to own portfolio. | RLS |

---

### SC-APP-001 — Rendering parity (HTML → Flutter)

**Required fixtures:** F-INV-01 (with F-ALC-01).
**Reference:** `Growize App Design.html`.
One case per screen — compare side-by-side, log mismatches as defects (default S3/S4 unless functional).

| # | Screen |
|---|---|
| 01 | Splash |
| 02 | Login / OTP |
| 03 | Onboarding |
| 04 | Home |
| 05 | Projects list |
| 06 | Project detail |
| 07 | Financials |
| 08 | Gallery |
| 09 | Documents |
| 10 | Activity |
| 11 | Profile |
| 12 | Support |
| 13 | Explore |
| 14 | Exit |
| 15 | Notifications |
| 16 | Settings |
| 17 | About / Legal |

---

### SC-DOC-001 — Documents per investor

**Required fixtures:** F-INV-01, F-INV-02, F-DOC-01.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-DOC-001-01 | Login as F-INV-01. | F-DOC-01 visible in documents list. | App |
| TC-DOC-001-02 | Login as F-INV-02. | F-DOC-01 NOT visible. | RLS |
| TC-DOC-001-03 | Open F-DOC-01 PDF. | Renders correctly; no broken signed URL. | App |

---

### SC-EXIT-001 — Exit and payout

**Required fixtures:** F-INV-01, F-PRJ-EXIT, F-ALC-EXIT.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-EXIT-001-01 | Verify F-PRJ-EXIT in Supabase. | Status Exit; payout fields populated. | Supabase |
| TC-EXIT-001-02 | Login as F-INV-01. | Project moves to Exit tab; payout principal + return shown. | App |
| TC-EXIT-001-03 | Verify amounts: paid + return = payout. | Math checks out. | App |

---

### SC-SYNC-001 — Sync correctness (NEW area)

**Goal:** Verify the sync pipeline is healthy, idempotent, and recovers from common failures. This is the heart of the daily UAT.

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-SYNC-001-01 | Query Supabase for the most recent `last_synced_at` across `-demo` records. | Older than now() but newer than now() − N minutes (configurable). | Sync |
| TC-SYNC-001-02 | Trigger sync edge function manually with a known `-demo` LLP ID. | Function returns 200; row in Supabase updated. | Sync |
| TC-SYNC-001-03 | Run sync edge function twice in quick succession. | No duplicate rows; idempotent. | Sync |
| TC-SYNC-001-04 | Inspect sync error log for last 24h. | Zero unhandled errors; non-zero retries are recovered. | Sync / Observability |
| TC-SYNC-001-05 | Verify schema migrations applied: `list_migrations` matches expected list. | No drift between staging and prod. | Supabase |

### SC-RLS-001 — Per-investor isolation (NEW)

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-RLS-001-01 | As F-INV-01, query `investor_units` table directly via Supabase client. | Returns only F-INV-01 rows. | RLS |
| TC-RLS-001-02 | As F-INV-01, attempt to read `investor_units` filtered by F-INV-02's id. | Empty result (RLS enforces, not just app filter). | RLS |
| TC-RLS-001-03 | As F-INV-01, attempt to read `documents` for F-INV-02. | Empty result. | RLS |
| TC-RLS-001-04 | Verify any `view`/`function` exposed to anon/auth role does NOT bypass RLS. | Audit-phase-1 fix verified. | RLS |
| TC-RLS-001-05 | Verify `-demo` records do NOT leak into a real (non-demo) investor's view. | Prod app filters out `-demo`. | App / RLS |

### SC-OBS-001 — Observability (NEW)

| Case ID | Step | Expected | Layer |
|---|---|---|---|
| TC-OBS-001-01 | Sentry: confirm app sends errors with environment + investor (anon) tag. | Recent errors visible in Sentry project. | Observability |
| TC-OBS-001-02 | Edge function logs: `get_logs` for past 24h. | Non-empty; no unhandled 500s. | Observability |
| TC-OBS-001-03 | Sync alert is wired to Slack on failure. | Test alert delivers. | Observability |

---

## §4. Negative / edge cases

| Case ID | Description | Expected |
|---|---|---|
| TC-NEG-001 | Sync paused. | App shows last-known data; resumes after sync. No crash. |
| TC-NEG-002 | Two CRM contacts share same email (F-INV-07). | Supabase + auth handle deterministically per spec; no two-user collision. File as S1 if collision. |
| TC-NEG-003 | Allocation removed from CRM. | App removes the row gracefully on next sync; totals recalc. |
| TC-NEG-004 | Project total_units < sum(allocated). | Daily UAT integrity check raises a defect. App still renders (no crash). |
| TC-NEG-005 | F-INV-06 logs in (zero allocations). | Empty-state screen; no crash. |
| TC-NEG-006 | Network offline. | Hive cache renders; offline banner shown. |
| TC-NEG-007 | Sync edge function returns 500. | App still loads cached data; alert fires. |
| TC-NEG-008 | Investor has 50+ projects. | List renders with pagination/scroll; no jank. (Performance smoke.) |
| TC-NEG-009 | Signed URL for document expired. | Re-fetch refreshes URL; user not blocked. |
| TC-NEG-010 | Two devices logged in as same investor (web + Android). | Both sessions show consistent data; no conflict. |

---

## Coverage matrix

| Area | Scenarios | Cases |
|---|---|---|
| LLP | 2 | 6 |
| Projects | 2 | 6 |
| Investors | 1 | 5 |
| Allocations (4 states + multi) | 5 | 19 |
| Auth & RLS | 1 | 5 |
| App parity (17 screens) | 1 | 17 |
| Documents | 1 | 3 |
| Exit | 1 | 3 |
| Sync (NEW) | 1 | 5 |
| RLS dedicated (NEW) | 1 | 5 |
| Observability (NEW) | 1 | 3 |
| Negative / edge | — | 10 |
| **Total** | **17** | **~87** |

A subset of these (~18 cases, all data-layer) make up the **Daily UAT** — see `DAILY_UAT_RUNBOOK.md`.
