-- ============================================================
-- MIGRATION 016 — Lock down gallery-sync cron with shared secret
--
-- Phase 1 audit found the live cron command for `gallery-sync-daily`
-- was sending only Content-Type — no Authorization, no shared secret.
-- The Edge Function had verify_jwt:false and no auth check, making it
-- publicly invokable. Fix mirrors the shared-secret pattern used by
-- `onboard-investor` and `zoho-crm-webhook`.
--
-- Secret stored in Supabase Vault (encrypted at rest); cron command
-- reads it via vault.decrypted_secrets each run. Edge Function compares
-- against the CRON_SECRET env var (set separately via dashboard/CLI).
--
-- Reversible:
--   DELETE FROM vault.secrets WHERE name='cron_secret';
--   SELECT cron.unschedule('gallery-sync-daily');
--   (then re-create with old command if rollback is required)
-- ============================================================

-- 1. Store the shared secret in Vault (encrypted at rest).
SELECT vault.create_secret(
  '362f7679765695d690b28a9c93bae93ed0d70f0299bd27e51180c4b072ac51ba',
  'cron_secret',
  'Shared secret for pg_cron → gallery-sync Edge Function authentication. Rotate by replacing the row in vault.secrets and updating CRON_SECRET in Edge Function env vars in lockstep.'
);

-- 2. Tear down the old (unauthenticated) cron job.
SELECT cron.unschedule('gallery-sync-daily');

-- 3. Re-schedule with x-arl-cron-secret header sourced from Vault.
SELECT cron.schedule(
  'gallery-sync-daily',
  '30 0 * * *',
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/gallery-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
