# DEF-12 — Server-side 5-year lock-in on exit_requests INSERT

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Commit:** 9ca6d80
**Migration:** supabase/migrations/20260513070000_044_exit_requests_lockin_rls.sql

## Problem
Migration 029 created the `exit_requests` INSERT policy as
`WITH CHECK (user_id = auth.uid())` — that authorises the row but
does not enforce the product rule that an investor can only request
an exit five years after the allocation's investment date. The
ExitScreen UI gates the CTA client-side, but a direct PostgREST POST
bypasses the gate completely.

## Decision
Drop and recreate the INSERT policy so it also requires the
referenced `investor_unit_id` to belong to the caller and to have
cleared `investment_date + interval '5 years'`:

```sql
DROP POLICY IF EXISTS "exit_requests: insert own" ON public.exit_requests;

CREATE POLICY "exit_requests: insert own"
  ON public.exit_requests FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
        FROM public.investor_units iu
       WHERE iu.id = investor_unit_id
         AND iu.investor_id = (SELECT auth.uid())
         AND iu.investment_date IS NOT NULL
         AND iu.investment_date + INTERVAL '5 years' <= NOW()
    )
  );
```

### Column choice
Per migration 003, `investor_units.investment_date DATE` is sourced
from Zoho's `Investment_Date`. No `issued_at` / `allocation_date`
column exists on this table — `investment_date` is the right one.

### Defence in depth
The Flutter UI gate stays. UI prevents the tap, RLS prevents the
write — either layer catches a malicious or buggy client.

## Verification
- `dart analyze lib` — clean (SQL-only change).
- Migration file saved locally; user applies via Supabase MCP.

## Rollback
```sql
DROP POLICY IF EXISTS "exit_requests: insert own" ON public.exit_requests;
CREATE POLICY "exit_requests: insert own"
  ON public.exit_requests FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
```
