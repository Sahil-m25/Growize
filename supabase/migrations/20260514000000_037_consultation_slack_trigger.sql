-- ============================================================
-- MIGRATION 037 — Slack notification on consultation request
--
-- After every INSERT on `public.consultation_requests` we POST the
-- new row's id to the `notify-consultation-request` Edge Function via
-- pg_net. The function looks up the project + investor (service role,
-- bypasses RLS), formats a Slack block payload, and posts it to the
-- webhook URL stored in the function's `SLACK_CONSULTATION_WEBHOOK_URL`
-- env var. If the env var is unset the function returns 200 — never
-- failing the trigger.
--
-- Why a trigger + edge function (not a direct client call): the user
-- can close the app between insert and post, dropping the notification.
-- pg_net retries failed posts up to a minute, so the trigger path is
-- robust even when the client disconnects right after insert.
--
-- Auth: same shared-secret pattern as the cron-driven functions —
-- `x-arl-cron-secret` header sourced from `vault.secrets.cron_secret`
-- (migration 016). No new credential needed.
--
-- Deploy ordering:
--   1. Set the edge function env vars in Supabase dashboard:
--        SLACK_CONSULTATION_WEBHOOK_URL = <user-provided Slack webhook>
--        CRON_SECRET                    = <value from vault.secrets.cron_secret>
--   2. Deploy: `supabase functions deploy notify-consultation-request --no-verify-jwt`
--   3. Apply this migration.
--
-- Reversible:
--   DROP TRIGGER trg_notify_consultation_request ON public.consultation_requests;
--   DROP FUNCTION public.notify_consultation_request();
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_consultation_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, pg_temp
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  -- Read the shared secret. If Vault isn't set up yet (fresh local
  -- DB) bail without raising — the consultation insert must succeed
  -- even if Slack plumbing is broken.
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'cron_secret not in vault; skipping Slack notify for consultation %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/notify-consultation-request',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-arl-cron-secret', v_secret
    ),
    body := jsonb_build_object('consultation_request_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_consultation_request
  ON public.consultation_requests;
CREATE TRIGGER trg_notify_consultation_request
  AFTER INSERT ON public.consultation_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_consultation_request();

COMMENT ON FUNCTION public.notify_consultation_request() IS
  'Posts a Slack notification to the consultation-requests webhook on '
  'every new consultation_requests row. Fires via pg_net to the '
  'notify-consultation-request Edge Function. SLACK_CONSULTATION_WEBHOOK_URL '
  'must be set on the function for the post to actually fire.';
