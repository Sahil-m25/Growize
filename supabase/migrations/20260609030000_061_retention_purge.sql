-- ============================================================
-- MIGRATION 061 — Purpose-bound retention (DPDP storage limitation)
--
-- Automated purge of transient/operational personal data beyond its
-- retention window. Runs weekly. DELIBERATELY EXCLUDES:
--   • KYC / financial records (investors, documents, payouts,
--     investor_units, exit_requests, bank_change_requests,
--     kyc_resubmissions) — statutory retention (PMLA / Companies / IT).
--   • consents — DPDP demonstrability record; kept for the relationship
--     + proof window.
--   • webhook_log — already purged by its own job.
--
-- Retention windows (recommended):
--   login_events            18 months  (>= the 1-year processing-log floor)
--   notifications           12 months  (transient UX data)
--   consultation_requests   24 months  (old / unconverted leads)
--
-- Function is SECURITY DEFINER (so the cron job can purge past RLS) and
-- EXECUTE is revoked from public/anon/authenticated (see migration 060).
-- ============================================================

create or replace function public.purge_expired_personal_data()
returns void
language plpgsql
security definer
set search_path = public
as $func$
begin
  delete from public.login_events
    where occurred_at < now() - interval '18 months';
  delete from public.notifications
    where created_at < now() - interval '12 months';
  delete from public.consultation_requests
    where created_at < now() - interval '24 months';
end;
$func$;

revoke execute on function public.purge_expired_personal_data()
  from public, anon, authenticated;

-- Weekly, Sundays 03:00 UTC (08:30 IST).
select cron.schedule(
  'purge-expired-personal-data',
  '0 3 * * 0',
  'select public.purge_expired_personal_data();'
);

-- Rollback:
--   select cron.unschedule('purge-expired-personal-data');
--   drop function if exists public.purge_expired_personal_data();
