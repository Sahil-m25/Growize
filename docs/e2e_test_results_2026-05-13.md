# Extended E2E Test Results — 2026-05-13

Run scope: post-soft-delete / notification-trigger / documents-tiering work.
Environment: cloud (Supabase production project), Flutter web build off
`main` at 79a93c3.

## Defects

| ID | Sev | Area | Title | Status |
|----|-----|------|-------|--------|
| DEF-08 | P1 | Zoho CRM | Allocation webhook missing custom function on `Customer_Status` | **Out of scope** — Zoho admin config change owned by user |
| DEF-09 | P1 | Edge / gallery-sync | `gallery-sync` queries non-existent `projects.zoho_llp_id` | **Fixed in commit be56f98** |
| DEF-10 | P2 | Schema / sync | `investor_units.deleted_at` missing — cancelled allocations have no soft-delete | **Fixed in commit bfda11e** (migration 042) |
| DEF-11 | P1 | Schema / triggers | `trg_bank_change_requests_updated_at` references non-existent column → all UPDATEs throw | **Fixed in commit 9b79be9** (migration 043) |
| DEF-12 | P2 | RLS / exit | 5-year lock-in is client-only; direct PostgREST POST bypasses it | **Fixed in commit 9ca6d80** (migration 044) |

## DEF-08 — Zoho allocation webhook custom function

P1. Allocation webhook does not invoke the `Customer_Status` recompute
custom function after status changes propagate from Books → CRM.
**Not fixed in this batch** — requires Zoho admin to attach the
function to the workflow rule in the CRM UI. Tracked separately.

## DEF-09 — gallery-sync queries non-existent column (FIXED)

`supabase/functions/gallery-sync/index.ts:107` selected
`projects.zoho_llp_id`. After the LLP/project schema split, the column
moved to `llps.zoho_llp_id` (FK via `projects.llp_id`). Fix joins
through the embedded relation:

```ts
.select("id, name, llp_status, llp:llps!inner(zoho_llp_id)")
.neq("llp_status", "completed")
.not("llp_id", "is", null);
```

Three downstream URL builds rewritten to use the resolved
`zohoLlpId` local. Deploy via Supabase MCP — not done here.

**Commit:** be56f98
**Decision:** `.claude/decisions/2026-05-13_def-09-gallery-sync-llp-join.md`

## DEF-10 — investor_units soft-delete column (FIXED)

Migration `20260513050000_042_investor_units_soft_delete.sql`:
- `ALTER TABLE public.investor_units ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`
- partial index `idx_investor_units_deleted_at WHERE deleted_at IS NOT NULL`
- drops/recreates the owner SELECT policy from migration 009 with
  `AND deleted_at IS NULL` filter, scoped to `authenticated`.

**Commit:** bfda11e
**Migration path:** `supabase/migrations/20260513050000_042_investor_units_soft_delete.sql`
**Decision:** `.claude/decisions/2026-05-13_def-10-investor-units-soft-delete.md`

## DEF-11 — bank_change_requests.updated_at column (FIXED)

Migration `20260513060000_043_bank_change_requests_updated_at.sql`:
- `ALTER TABLE public.bank_change_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Picks Option A (add the column) because every other table with the
`set_updated_at` trigger already has the column. The trigger is the
project convention; the column was the schema outlier. Unblocks the
notification trigger from migration 041.

**Commit:** 9b79be9
**Migration path:** `supabase/migrations/20260513060000_043_bank_change_requests_updated_at.sql`
**Decision:** `.claude/decisions/2026-05-13_def-11-bank-change-updated-at.md`

## DEF-12 — Server-side 5-year lock-in on exit_requests (FIXED)

Migration `20260513070000_044_exit_requests_lockin_rls.sql`:
- drops + recreates the migration 029 INSERT policy with a
  `WITH CHECK` that also requires the referenced `investor_unit_id`
  to belong to the caller and to have cleared
  `investment_date + interval '5 years'`. Column is `investment_date`
  (DATE) per migration 003.

**Commit:** 9ca6d80
**Migration path:** `supabase/migrations/20260513070000_044_exit_requests_lockin_rls.sql`
**Decision:** `.claude/decisions/2026-05-13_def-12-exit-lockin-rls.md`

## Verification

- `dart analyze lib` — clean across all four commits.
- Migrations 042-044 saved locally; user applies via Supabase MCP.
- gallery-sync redeploy deferred to the user.
