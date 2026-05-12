-- ============================================================
-- MIGRATION 022 — Schedule health-check cron job
--
-- Daily cron job that queries webhook_log and cron.job_run_details
-- for failures in the last 24 hours. If found, sends an ops email.
-- Uses the same shared-secret pattern as gallery-sync: reads secret
-- from vault and includes in x-arl-cron-secret header.
--
-- Reversible:
--   SELECT cron.unschedule('health-check-daily');
-- ============================================================

-- Schedule the health-check function.
-- Time: 07:00 UTC = 12:30 IST
SELECT cron.schedule(
  'health-check-daily',
  '0 7 * * *',
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/health-check',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
