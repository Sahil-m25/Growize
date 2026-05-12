-- ============================================================
-- MIGRATION 024 — schedule reconcile + stale-alert crons
--
-- zoho-reconcile-daily : 01:00 UTC daily (06:30 IST). Pulls from Zoho
--                         CRM and upserts any rows where Supabase has
--                         not seen the latest Modified_Time. Pull-side
--                         safety net for the push webhook.
--
-- sync-stale-alert      : hourly. Reads sync_status view; inserts a
--                         sync_alerts row when any monitored table's
--                         max(last_synced_at) exceeds threshold.
--
-- Both use the same `cron_secret` Vault entry that gallery-sync and
-- health-check already use. Mirrors the pattern in
-- 014_enable_pg_cron_and_schedule.sql + 022_health_check_cron.sql.
-- ============================================================

-- zoho-reconcile-daily — pull-side fallback
SELECT cron.schedule(
  'zoho-reconcile-daily',
  '0 1 * * *',
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);

-- sync-stale-alert — staleness observability, hourly
SELECT cron.schedule(
  'sync-stale-alert-hourly',
  '0 * * * *',
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/sync-stale-alert',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
