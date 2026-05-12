# Daily UAT Runbook

**Owner:** ARL Tech
**Cadence:** Every day at 06:00 IST
**Mode:** Hybrid — automated data-layer checks daily; human full-app pass weekly + pre-release.
**Companion to:** `TEST_PLAN.md`, `SCENARIOS.md`, `ARL_Test_Tracker.xlsx` (Daily UAT sheet).

---

## Purpose

Catch regressions before users hit them. The daily run focuses on **data-layer correctness, sync health, RLS isolation, and integrity invariants** — the things that can silently rot between deployments. Anything that requires a human eye (rendering parity, copy review, gallery image quality) belongs to the **weekly human pass**.

## How it runs

### Daily loop (automated)

A scheduled task (Cowork scheduled-task or a Supabase cron + Slack hook, owner's choice) executes the **Daily UAT case set** below and writes one column per day into the `Daily UAT` sheet of `ARL_Test_Tracker.xlsx`.

For each case, the agent:

1. Calls Supabase / edge function with the credentials of a designated **daily-UAT service account** (a real onboarded auth user mapped to fixture `F-INV-01`).
2. Asserts the expected condition.
3. Records `Pass` / `Fail` / `Skipped` with a short reason.
4. On Fail → posts to Slack `#growize-test`, opens (or updates) a defect candidate.

### Weekly loop (human)

A tester runs the full `Test Cases` sheet — primarily the rendering-parity scenarios (`SC-APP-001`) and anything not safely automatable (PDF visual check, gallery quality, exit screen polish).

### Pre-release loop (human)

Same as weekly, but also runs the negative / edge cases. Required before any production deployment.

---

## Daily UAT case set (the ~18 the agent runs every day)

These are extracted from `SCENARIOS.md`. They cover sync, RLS, allocation invariants, observability — all without needing eyes.

| ID | Source case | What the agent asserts |
|---|---|---|
| D-01 | TC-SYNC-001-01 | `max(last_synced_at)` for `-demo` rows is within last 30 minutes. |
| D-02 | TC-SYNC-001-04 | Edge function error log for last 24h has zero unhandled 500s. |
| D-03 | TC-SYNC-001-05 | `list_migrations` output matches the pinned expected list (no drift). |
| D-04 | TC-RLS-001-01 | Logged in as F-INV-01, query `investor_units` returns only F-INV-01's rows (count matches expected). |
| D-05 | TC-RLS-001-02 | Logged in as F-INV-01, query `investor_units where investor_id = F-INV-02` returns 0 rows. |
| D-06 | TC-RLS-001-03 | Documents query as F-INV-01 cannot see F-INV-02's documents. |
| D-07 | TC-RLS-001-05 | Production-like investor session does NOT see any `-demo` records. |
| D-08 | TC-ALC-001-01 | F-ALC-01 row exists with payment_status=Paid; units, amounts match fixture spec. |
| D-09 | TC-ALC-002-01 | F-ALC-02 + F-PRJ-A2 status is `not_started`; allocation Paid. |
| D-10 | TC-ALC-003-01 | F-ALC-03 has paid_amount = 0; status = Pending. |
| D-11 | TC-ALC-004-01 | F-ALC-04 has paid = 50% committed; status Partial. |
| D-12 | TC-ALC-005-01 | F-INV-05 has 2 allocations; sums match fixture spec. |
| D-13 | TC-NEG-004 | Integrity invariant: for every project, `sum(allocated_units) ≤ project.total_units`. |
| D-14 | (new) | Integrity invariant: for every allocation, `paid_amount ≤ committed_amount`. |
| D-15 | (new) | Integrity invariant: every allocation FK resolves (no orphan investor_id or project_id). |
| D-16 | TC-OBS-001-02 | Edge-function logs not empty for last 24h. |
| D-17 | TC-OBS-001-03 | Slack alert webhook responded 200 in the last test fire. |
| D-18 | TC-EXIT-001-01 | F-PRJ-EXIT status Exit; payout fields populated. |

The agent must complete all 18 in under 60 seconds on a healthy system.

---

## Result format

Each daily run appends a column to `Daily UAT` sheet, header = `YYYY-MM-DD`. Each row is one case (D-01..D-18). Cell value is `Pass` / `Fail` / `Skipped`. A summary row at the bottom shows pass count / total.

In Slack, the agent posts:

```
🌱 Growize Daily UAT — 2026-05-06
Result: 17/18 PASS
Failed: D-04 (RLS — F-INV-01 saw 12 allocations, expected 1)
Defect candidate: DEF-NEW (S1)
Run time: 38s
```

---

## Failure thresholds

| Failure pattern | Action |
|---|---|
| 1 case fails for 1 day | Investigate same day; file defect; do NOT block deploys yet. |
| Same case fails 2 days in a row | Block deploys until resolved. |
| Any S1-equivalent fails (RLS leak, money math, auth bypass) | Block deploys immediately, page on-call. |
| 3+ cases fail same day | Investigate sync/infra incident first. |

---

## Service account & secrets

- Daily-UAT auth user is a real onboarded investor (mapped to F-INV-01) with email `daily-uat-demo@arl.test`.
- OTP is bypassed for this account using a dedicated long-lived token stored in the scheduler's secret manager. Token is rotated quarterly.
- Slack webhook URL stored in same secret manager.

---

## What this runbook does NOT cover

- Rendering parity (weekly human pass).
- Gallery / image quality (weekly).
- PDF visual fidelity (weekly).
- Push notification delivery (weekly + pre-release).
- App version upgrade flow (pre-release).
- Localization (pre-release).
- Performance / cold start (pre-release).

These belong to the weekly + pre-release loops. The tracker's `Test Cases` sheet flags them with priority P0/P1.

---

## Maintenance

When a fixture changes (new investor, new project, new allocation state added), update:

1. `SCENARIOS.md` §2 fixture spec.
2. `Fixture Spec` sheet of the tracker (CRM ID column).
3. The corresponding `D-##` assertion in this runbook (case set table above).
4. The agent's code (assertion list).

When a new daily case is added, add it to the case-set table above and to the `Daily UAT` sheet rows.
