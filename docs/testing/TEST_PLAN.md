# Growize App — Test Plan

**Owner:** ARL Tech
**Created:** 2026-05-05 (revised)
**Status:** Active
**Test cycle:** Pre-production launch (target 2026-05-05) + ongoing daily UAT

---

## 1. Purpose

Validate that the Growize Flutter investor portal renders Zoho CRM data correctly via Supabase, that all four allocation states are handled, that no investor sees another investor's data, and that the system can be re-tested on a daily cadence to catch regressions before users hit them.

## 2. Ground Rules

### Rule 1 — CRM data is observed, not modified

- **Production records in Zoho CRM are NEVER edited or deleted as part of testing.**
- CRM is treated as the upstream source-of-truth. We read what is there. We do not fix issues by editing CRM records.
- Fixes for any test failure go into **Supabase schema, sync logic, RLS, edge functions, or the Flutter app** — never the CRM record.

### Rule 2 — Demo records get a `-demo` suffix

- New test fixtures CAN be created in CRM, but every record's name MUST end with `-demo`.
- Examples: `Alpha Agro LLP-demo`, `Mango Orchard-demo`, `Aarav Sharma-demo`, `Allocation-A1-demo`.
- The `-demo` suffix is the canonical filter for separating real production data from test data, both in CRM views and in Supabase queries.
- All sync logic, dashboards, and audit reports must respect this filter (or have an explicit toggle to include demo data).

### Rule 3 — Investigate top-down, fix bottom-up

When a test fails, walk the layers in order:

1. Confirm the `-demo` record exists in CRM with the expected field values (observation only).
2. Confirm sync ran (logs, last-sync timestamp).
3. Confirm Supabase has the row with correct values, FKs, and RLS scope.
4. Confirm the Flutter app reads and renders it correctly.

The fix lives at whichever layer is wrong, except CRM. If CRM data is wrong, file a defect at the **Sync** layer (i.e., our pipeline should handle that CRM state) — do not edit the CRM record.

## 3. Scope

### In scope

- LLP, Project, Investor, Allocation visibility from CRM `-demo` records → Supabase → app.
- All four allocation/payment states (Paid+Active, Paid+NotStarted, Pending, Partial).
- Multi-project / multi-LLP investor aggregation.
- Authentication and per-investor data isolation (RLS).
- Read paths in the Flutter app on Android + Chrome.
- Documents and gallery rendering.
- Project state transitions (Not Started → Active → Exit).
- Negative / edge / boundary cases.
- Observability (Sentry, sync job logs).
- **Daily automated data-layer checks** (hybrid model — see §6).
- **Weekly human UAT pass** of the full app.

### Out of scope (this cycle)

- Realtime updates (project decision: never).
- App write operations (read-heavy app).
- iOS-specific platform behaviour.
- Performance/load testing beyond functional smoke checks.
- PostHog analytics — see `BACKLOG.md`.

## 4. Test Environments

| Environment | CRM | Supabase | App | Purpose |
|---|---|---|---|---|
| **Dev** | Zoho production (read-only obs.) | Supabase dev project | `flutter run -d chrome` | Iterative test of new cases |
| **Staging** | Zoho production (read-only obs.) | Supabase staging | Web build + Android APK | Full regression before sign-off |
| **Prod** | Zoho production | Supabase production | Released build | Smoke + sign-off + daily UAT |

`-demo` records can live in any of these — they are filtered, not separated.

## 5. Roles

| Role | Responsibility |
|---|---|
| Test author | Writes scenarios and fixture spec; updates docs as flows change. |
| Tester (human) | Runs weekly full UAT and pre-release passes; investigates daily-UAT failures. |
| Daily-UAT agent | Scheduled task that runs data-layer checks every day and posts results. |
| Triage | Assigns severity/priority to defects, routes to dev. |
| Dev | Investigates, fixes, requests re-test. |
| Verifier | Re-runs failed cases after fix; closes defects. |

## 6. Hybrid Test Cadence

Two parallel test loops:

### Loop A — Daily automated data-layer UAT

- Runs every day at a fixed time (target 06:00 IST).
- Executes ~15–20 cases that don't need a human eye: sync freshness, RLS isolation, allocation invariants, edge function health, schema drift checks.
- Posts a pass/fail row to the **Daily UAT** sheet of the tracker (one column per day).
- Failures generate a Slack alert and a defect candidate.
- See `DAILY_UAT_RUNBOOK.md` for the exact runbook.

### Loop B — Weekly human full UAT

- Runs every Monday morning + before any release.
- Walks through every screen with seeded `-demo` fixtures.
- Includes app rendering parity, copy review, gallery/PDF rendering — anything the daily agent can't see.
- Result captured in the **Test Cases** sheet of the tracker.

The two loops share the same scenarios, fixtures, and defect log.

## 7. Entry Criteria (pre-launch)

- Supabase schema deployed; sync edge functions live.
- App build is installable.
- `-demo` fixture set seeded in CRM (per fixture spec — see `SCENARIOS.md`).
- Sync has run at least once and reflected the demo records into Supabase.

## 8. Exit Criteria (pre-launch)

- 100% of P0 cases passed.
- 100% of P1 cases passed.
- ≤ 5% P2 cases open, each with workaround documented.
- Zero open S1 defects; zero open S2 defects (or workaround documented).
- Daily UAT runs cleanly for 3 consecutive days before launch.
- Defect log signed off by ARL Tech.

## 9. Test Artefacts

| Artefact | Location | Purpose |
|---|---|---|
| Test plan | `docs/testing/TEST_PLAN.md` | This document — strategy and rules. |
| Scenarios + cases | `docs/testing/SCENARIOS.md` | Business flows, fixture spec, detailed cases. |
| Daily UAT runbook | `docs/testing/DAILY_UAT_RUNBOOK.md` | Exact steps the scheduled agent follows. |
| Defect log + template | `docs/testing/DEFECT_LOG.md` | Index + per-defect markdown format. |
| Backlog | `docs/testing/BACKLOG.md` | Deferred items (PostHog, etc.). |
| Execution tracker | `ARL_Test_Tracker.xlsx` (repo root) | Live pass/fail tracker, dashboard, daily-UAT log. |
| Defect entries | `docs/testing/defects/DEF-####.md` | One markdown per defect, mirrored in tracker. |

## 10. Severity & Priority

### Severity (impact)

| Level | Definition |
|---|---|
| **S1 — Critical** | Wrong investor sees wrong data. Auth bypass. App crash on launch. Money figures wrong by more than rounding. |
| **S2 — High** | Core flow broken (allocation, project view) but no data leak. Sync silently failing. |
| **S3 — Medium** | Single state of allocation miscomputed. Cosmetic gap with workaround. |
| **S4 — Low** | Copy issue, minor UI parity (spacing, color). |

### Priority (urgency)

| Level | Definition |
|---|---|
| **P0** | Blocks launch — must fix before 2026-05-05. |
| **P1** | Fix in current cycle. |
| **P2** | Fix in next sprint. |
| **P3** | Backlog. |

## 11. Defect Workflow

1. Tester (or daily-UAT agent) reproduces the issue twice.
2. File defect in tracker `Defects` sheet **and** as `docs/testing/defects/DEF-####.md`.
3. Capture: layer (Sync / Supabase / App / Auth / RLS / Mixed), severity, priority, repro steps, screenshot reference, expected vs actual.
4. Triage assigns owner.
5. Dev investigates → fills RCA + fix.
6. Tester re-tests → marks Pass / Fail-again.
7. Closed only after re-test pass.

## 12. Reporting

End-of-day status (auto-posted by daily-UAT agent + manual append by tester):

```
Date:
Daily UAT result: PASS / FAIL (X/Y cases)
Cases executed (manual):
Passed / Failed / Blocked:
New defects (S1/S2/S3/S4):
Closed defects:
Top concerns:
```

## 13. Risk Register

| Risk | Mitigation |
|---|---|
| Demo data leaks into a real investor's view | Every Supabase query that powers the app must filter by investor + exclude `-demo` for prod users (or apply explicit demo persona toggle). Daily-UAT case verifies. |
| Sync drops a CRM update | Daily-UAT case checks sync freshness for known `-demo` records. Alert if last_sync > N minutes. |
| Schema drift between staging and prod | List_migrations check in daily UAT. Pre-launch parity audit. |
| RLS misconfiguration after migration | Daily-UAT RLS isolation case. Phase-1 audit findings already filed. |
| Demo persona contamination | Fixed `-demo` suffix rule + filter in app build. |

---

## Linked documents

- `SCENARIOS.md` — fixture spec, scenarios, detailed cases.
- `DAILY_UAT_RUNBOOK.md` — what the agent runs each morning.
- `DEFECT_LOG.md` — defect template and index.
- `BACKLOG.md` — deferred work.
- `ARL_Test_Tracker.xlsx` — execution dashboard.
