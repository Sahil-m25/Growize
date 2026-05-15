# Decision — Ops-doc consolidation + two safe DB fixes

**Date:** 2026-05-15
**Status:** locked
**Owner:** Claude (Opus 4.7), reporting to ARL Tech

## Context

ARL has limited dev capacity. The only operator for the foreseeable future is non-developer. `docs/ops_admin_guide.md` (1070 lines) was a single-file master, but four workflows kept growing past their inline budget: support tickets, marketplace project lifecycle, document tiering, and full investor-profile management. Ops needed a "you can do everything from here" manual with concrete SQL + Studio walkthroughs.

## Decision

Split the four deep workflows into per-topic docs under `docs/ops/`, keep `docs/ops_admin_guide.md` as the master index, and add Part 10 to the master pointing at each. Run all four investigations live against `oynfhdqizebvgmaoiuax` so the SQL recipes are real.

Files:
- `docs/ops/tickets.md` — 709 lines
- `docs/ops/marketplace.md` — 816 lines
- `docs/ops/documents.md` — 563 lines
- `docs/ops/investor_profile.md` — 1012 lines
- `docs/ops_admin_guide.md` — Part 10 appended with TOC, per-topic summaries, and defect roll-up table

Ship two safe DB fixes surfaced during the live tests:
- Migration 045 widens `notify_exit_request_status_change()` to fire for any transition into a terminal state (fixes DEF-OPS-2 — approved→settled no notification).
- Migration 045 sets `DEFAULT 0` on `projects.units_issued` + `units_available` and backfills three NULL UAT rows (fixes DEF-MKT-03).

Defer:
- Auto-balance for `projects.units_available` — a recompute trigger on `investor_units` would race the Zoho LLP webhook (which writes `units_issued` authoritatively on every LLP save). Documented in `docs/ops/marketplace.md` §6 as a future planned change paired with a `GENERATED` column AND removing the webhook's write to `units_available`.
- DOC-RLS-PATH (P1) — seed `documents.storage_path` values use `documents/` prefix but storage RLS reads folder level 1. Bucket is empty so latent. Needs engineering judgement: drop the prefix in seed rows OR widen the RLS predicate.
- DEF-MKT-01 (P1) — `Sample Test LLP` `units_available = -30`. Adding CHECK constraints would reject existing data; needs data cleanup first.

## Live verification

- 4 docs written using the Supabase execute_sql MCP against the live DB and Chrome MCP against the dev build at `http://localhost:5500`.
- All test rows (tickets, exit_requests, bank_change_requests, documents) inserted on the test investor or self-Claude account, then DELETEd as cleanup. Test investor state confirmed back to baseline.
- Migration 045 applied via apply_migration MCP. Post-apply check: `SELECT COUNT(*) FROM projects WHERE units_issued IS NULL OR units_available IS NULL` returned 0.

## Defects surfaced

18 new rows in `ARL_Test_Tracker.xlsx` -> Defects sheet (DEF-2026-05-15-01..18). Two infra rows on Launch Readiness (LR-OPS-001, LR-DB-045). Both DEF-MKT-03 and DEF-OPS-2 marked Resolved.

## Open questions logged

- Should ops-initiated tickets via Recipe T-6 also send a Resend email? Today only edge functions email.
- Realtime subscription on ticket providers — adopt as the first such subscription in the codebase?
- Webhook-to-auth-users email sync — when do we ship the admin.updateUserById call inside zoho-crm-webhook?
- Retention policy on notifications — none today; should grow without bound.

## Rollback

- Migration 045 rollback: restore the prior notify_exit_request_status_change() body from migration 034; ALTER TABLE projects ALTER COLUMN units_issued DROP DEFAULT and units_available DROP DEFAULT. The NULL backfill is one-way.
- Doc rollback: delete docs/ops/*.md and revert the Part 10 block in docs/ops_admin_guide.md.
