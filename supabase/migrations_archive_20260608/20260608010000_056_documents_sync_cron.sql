-- ============================================================
-- MIGRATION 056 — Schedule documents-sync daily
--
-- Authenticated with the shared cron secret already stored in
-- Vault by migration 016 (the same secret gallery-sync uses).
-- The Edge Function compares the x-arl-cron-secret header against
-- its CRON_SECRET env var.
--
-- Runs at 00:45 UTC (06:15 IST) — 15 minutes after gallery-sync
-- (00:30 UTC) so the two functions don't refresh the Zoho token
-- in the same instant.
--
-- Prerequisite: deploy the function first, and ensure CRON_SECRET
-- is set in its env (reuse the gallery-sync value):
--   supabase functions deploy documents-sync --no-verify-jwt
--   supabase secrets set CRON_SECRET=<vault.cron_secret value>
--
-- Reversible:
--   SELECT cron.unschedule('documents-sync-daily');
-- ============================================================

SELECT cron.schedule(
  'documents-sync-daily',
  '45 0 * * *',
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/documents-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
