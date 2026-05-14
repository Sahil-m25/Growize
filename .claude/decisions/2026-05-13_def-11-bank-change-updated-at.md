# DEF-11 — bank_change_requests.updated_at column

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Commit:** 9b79be9
**Migration:** supabase/migrations/20260513060000_043_bank_change_requests_updated_at.sql

## Problem
Migration 010 attached
`trg_bank_change_requests_updated_at BEFORE UPDATE … EXECUTE FUNCTION public.set_updated_at()`
to the table, but the original CREATE TABLE in migration 006 never
included an `updated_at` column. Every UPDATE therefore raised
`record "new" has no field "updated_at"`, so ops could not transition
requests from pending → approved/rejected. The downstream effect:
the status-change notification trigger we shipped in migration 041
never fires, because the row never updates.

## Decision — Option A: add the column
Every other table that has the `set_updated_at` trigger
(`investors`, `projects`, `investor_units`, `payouts`, `project_phases`,
`crops`, `support_tickets`, `app_config`) carries an `updated_at`.
The trigger is the convention; `bank_change_requests` is the outlier.
Aligning the schema is the correct fix.

```sql
ALTER TABLE public.bank_change_requests
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
```

`IF NOT EXISTS` + `DEFAULT NOW()` keep the migration safe to re-run
and backfill existing rows in one shot.

## Why not Option B (drop the trigger)
The trigger encodes a real ops need: notifications fire on
`updated_at` change. Dropping it would silence DEF-12's notification
path again. The column is what was missing.

## Verification
- `dart analyze lib` — clean (SQL-only change).
- Migration file saved locally; user applies via Supabase MCP.

## Rollback
- `ALTER TABLE public.bank_change_requests DROP COLUMN IF EXISTS updated_at;`
  (existing trigger from migration 010 will then break again — leave
  the trigger drop to the caller if that is intended.)
