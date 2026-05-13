# sync_status view → SECURITY INVOKER — remediate S-003

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Audit finding:** S-003 (High) — `docs/security_audit_2026-05-13.md`

## Problem
Supabase advisor flagged `public.sync_status` as a `security_definer_view`.
The view (defined at the bottom of migration 023) inherits Postgres's
default view-evaluation mode, where the view runs with the
view-owner's privileges (`postgres`, BYPASSRLS) rather than the
caller's. Any authenticated caller would see the full unfiltered
aggregate over llps / projects / investors / investor_units.

## Decision
Flip the view to `SECURITY INVOKER` (one-line `ALTER VIEW … SET
(security_invoker = on)`). Same fix migration 015 applied to
`portfolio_summary`.

Considered and rejected: keeping SECURITY DEFINER and adding an
`auth.jwt()` role gate inside the view body. Rejected because:
1. All current consumers are service_role (health-check edge fn,
   sync-stale-alert cron, ops UAT) which bypass RLS regardless.
2. No app-side authenticated caller reads `sync_status`. So
   SECURITY INVOKER costs nothing today.
3. If a future ops dashboard for staff needs cross-user aggregates,
   that should be a separate view or RPC with an explicit role gate,
   not a tweak buried in this view's body.

## Touched files
- `supabase/migrations/20260513000100_035_sync_status_security_invoker.sql` (new)

No client-side changes. No edge function changes. health-check and
sync-stale-alert continue to read the view via service_role — RLS
bypass means the result set is identical.

## Verification
- Supabase advisor (`Studio → Advisors`) — the
  `security_definer_view` warning on `public.sync_status` must
  clear.
- `SELECT reloptions FROM pg_class WHERE relname='sync_status';`
  must contain `security_invoker=on`.
- Smoke `select * from public.sync_status` from service_role
  returns the four-row aggregate as before.

## Rollback
- `ALTER VIEW public.sync_status SET (security_invoker = off);`
