-- ============================================================
-- MIGRATION 035 — sync_status view SECURITY INVOKER (S-003 remediation)
--
-- Audit finding S-003 (docs/security_audit_2026-05-13.md): the
-- `public.sync_status` view (defined in migration 023) inherited
-- Postgres's default view-evaluation mode, which is effectively
-- SECURITY DEFINER — the view runs with the owner's (postgres)
-- privileges, bypassing the caller's RLS context. Same posture
-- migration 015 already corrected for `portfolio_summary`.
--
-- The view aggregates COUNT(*) and MAX(last_synced_at) across
-- llps / projects / investors / investor_units. Its consumers are:
--   * health-check edge function (service_role — RLS doesn't apply).
--   * sync-stale-alert cron       (service_role — RLS doesn't apply).
--   * Daily UAT D-01 runbook check (run by ops — same).
--
-- None of these regress when the view switches to SECURITY INVOKER,
-- because service_role bypasses RLS regardless of the view setting.
-- For any future authenticated caller, the view will now correctly
-- scope to that user's RLS-visible rows (counts/max stay accurate
-- within the caller's slice of data).
--
-- Reversible: ALTER VIEW public.sync_status SET (security_invoker = off);
-- ============================================================

ALTER VIEW public.sync_status SET (security_invoker = on);

COMMENT ON VIEW public.sync_status IS
  'Per-table sync freshness snapshot. SECURITY INVOKER — relies on '
  'RLS on the underlying llps/projects/investors/investor_units '
  'tables when accessed via an authenticated session. Consumers are '
  'service_role only (health-check + sync-stale-alert + UAT D-01), '
  'which bypass RLS, so the practical row set is unchanged. DO NOT '
  'flip back to security_invoker=off without auditing the leak vector '
  'first — see docs/security_audit_2026-05-13.md S-003.';

-- Verification (post-apply):
--   SELECT reloptions FROM pg_class WHERE relname='sync_status';
--   -- must contain 'security_invoker=on'
--
--   Supabase advisor: the `security_definer_view` warning on
--   public.sync_status must no longer appear in the Security report.
