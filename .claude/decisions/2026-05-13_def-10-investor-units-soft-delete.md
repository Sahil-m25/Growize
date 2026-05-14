# DEF-10 — investor_units.deleted_at soft-delete column

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Commit:** bfda11e
**Migration:** supabase/migrations/20260513050000_042_investor_units_soft_delete.sql

## Problem
The soft-delete pattern shipped in migrations 037-038 (mirrored from
the Zoho CRM soft-delete propagation work) covered investors and
projects but not `investor_units`. Cancelled allocations had no
in-band representation — deleting the row would break FK integrity
with `payouts` and `exit_requests`, and ops needed to keep cancelled
allocations for payout audit history.

## Decision
Add a nullable `deleted_at TIMESTAMPTZ` column with a partial index,
following the same convention as the 037-038 tables:

```sql
ALTER TABLE public.investor_units
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_investor_units_deleted_at
  ON public.investor_units (deleted_at)
  WHERE deleted_at IS NOT NULL;
```

Amend the owner-facing SELECT policy from migration 009 to filter
`deleted_at IS NULL`, so cancelled rows are invisible to the
investor while preserving FK targets for audit/payout views.

```sql
DROP POLICY IF EXISTS "investor_units: read own rows" ON public.investor_units;
CREATE POLICY "investor_units: read own rows"
  ON public.investor_units FOR SELECT
  TO authenticated
  USING (
    investor_id = (SELECT auth.uid())
    AND deleted_at IS NULL
  );
```

The policy was bound to the public role originally; the recreate also
scopes it to `authenticated`, matching the 018+ tightening.

## Verification
- `dart analyze lib` — clean (SQL-only change).
- Migration file saved locally; user applies via Supabase MCP.

## Rollback
- `DROP INDEX IF EXISTS public.idx_investor_units_deleted_at;`
- `ALTER TABLE public.investor_units DROP COLUMN IF EXISTS deleted_at;`
- Recreate the prior SELECT policy from migration 009.
