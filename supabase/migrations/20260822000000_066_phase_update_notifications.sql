-- ============================================================
-- MIGRATION 066 — PROJECT PHASE UPDATE NOTIFICATIONS
--
-- Adds the missing link between `project_phases` and the in-app
-- activity feed. Until now nothing anywhere inserted a stage /
-- milestone notification: the `milestone` type was legal per the
-- CHECK constraint from migration 006 but had zero writers, and
-- the `phase_update` flow described in
-- `docs/ops/data_sources_guide.md` (handleLlp, phase_timeline_10,
-- 2026-05-19_phase_backfill.sql) was never implemented.
--
-- What this migration does:
--   0. Widens notifications.type — see the note on `document`
--      below, this also repairs a live silent failure.
--   1. Adds notify_project_phase_change(), a SECURITY DEFINER
--      fan-out that writes one notification per investor holding
--      units in the project when a phase becomes `current`.
--   2. Wires it to project_phases.
--
-- VERIFIED AGAINST PRODUCTION 2026-08-22 (project oynfhdqizebvgmaoiuax,
-- "Growize Main DB", Postgres 17.6):
--   * notifications_type_check ALREADY lists phase_update / document /
--     new_project. Section 0 below is therefore a no-op on that database
--     — it re-asserts the identical set. Kept so the migration is
--     self-contained for any environment still on the 034 constraint.
--     (Corollary: the documents-sync silent-failure described in
--     section 0 was already fixed in prod; `document` notifications are
--     live there. No backlog is released by applying this.)
--   * project_phases has NO trigger other than trg_project_phases_updated_at,
--     and zero rows. Nothing here collides.
--   * project_phases in prod has NO started_at / completed_at columns —
--     archived migration 053 was never applied there. This migration does
--     not touch those columns, so it works either way.
--   * investor_units carries a deleted_at soft-delete column, so the
--     fan-out filters on it (see section 1).
--
-- Delivery is IN-APP ONLY. There is no push transport in this
-- codebase (lib/core/notifications/fcm_service.dart is a no-op
-- stub, there is no device_tokens table and no notify-push
-- function). Investors see these the next time they open the
-- app. Native push is scoped separately in
-- `docs/plans/2026-08-22_push_notifications_fcm_scope.md`.
-- ============================================================

-- ------------------------------------------------------------
-- 0) Widen notifications.type CHECK.
--
-- Previous list came from migration 034:
--   payout, photo, ticket, reminder, milestone, kyc, exit, bank_change
--
-- Added here:
--   phase_update — written by the trigger below.
--   document     — already present in the Growize Main DB constraint
--                  (verified 2026-08-22), where document notifications
--                  are live. Listed here because the repo's migration
--                  history stops at 034's narrower list, so any
--                  environment rebuilt from these files would otherwise
--                  reject the type='document' inserts that
--                  supabase/functions/documents-sync/index.ts has been
--                  making since v32 — silently, since that function
--                  never checks the returned error.
--   new_project  — reserved for the marketplace broadcast described in
--                  data_sources_guide section 3. No writer yet; listed
--                  so a future edge function does not repeat the
--                  `document` mistake.
-- ------------------------------------------------------------
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN ('payout', 'photo', 'ticket', 'reminder', 'milestone',
             'kyc', 'exit', 'bank_change',
             'phase_update', 'document', 'new_project')
  );

-- ------------------------------------------------------------
-- 1) Fan-out function.
--
-- Fires only on the transition INTO `current` — an edit that
-- touches a row already sitting at `current` is a no-op, so
-- ops re-saving a phase in Studio does not re-notify.
--
-- Idempotent per (investor, project, stage_index): a replayed
-- Zoho webhook, a re-run backfill, or a phase bounced
-- pending -> current -> pending -> current will not produce a
-- duplicate card in the investor's feed.
--
-- Respects the investor's own `user_settings.notifications_enabled`
-- toggle (Profile > Security > Notifications). Investors with no
-- settings row COALESCE to TRUE — the row is only written when a
-- user actually flips a toggle, so treating "absent" as "off"
-- would silence almost everybody.
--
-- SECURITY DEFINER + pinned search_path matches the pattern
-- established by migration 034's notification triggers.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_project_phase_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_project_name TEXT;
  v_stage_label  TEXT;
  v_title        TEXT;
  v_body         TEXT;
  v_meta         JSONB;
  v_notified     INT;
BEGIN
  -- Only a phase that IS current is newsworthy.
  IF NEW.status IS DISTINCT FROM 'current' THEN
    RETURN NEW;
  END IF;

  -- Already current before this write -> unrelated edit, stay quiet.
  IF TG_OP = 'UPDATE' AND OLD.status = 'current' THEN
    RETURN NEW;
  END IF;

  -- Soft-deleted project -> nobody to tell.
  SELECT p.name INTO v_project_name
  FROM public.projects p
  WHERE p.id = NEW.project_id
    AND p.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  v_stage_label := COALESCE(NULLIF(TRIM(NEW.phase_name), ''), 'a new stage');

  v_title := 'Stage update: ' || v_stage_label;
  v_body  := COALESCE(v_project_name, 'Your project')
             || ' has moved to ' || v_stage_label || '.';

  -- cta_route / cta_label are read by _NotifCard in
  -- lib/features/activity/activity_screen.dart to render the
  -- "View Project" button. Route matches the GoRouter path
  -- /projects/:id registered in core/navigation/router.dart.
  v_meta := jsonb_build_object(
    'project_id',   NEW.project_id,
    'project_name', v_project_name,
    'stage_index',  NEW.sort_order,
    'phase_name',   NEW.phase_name,
    'cta_route',    '/projects/' || NEW.project_id::TEXT,
    'cta_label',    'View Project'
  );

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT DISTINCT
         iu.investor_id,
         'phase_update',
         v_title,
         v_body,
         v_meta
  FROM public.investor_units iu
  LEFT JOIN public.user_settings us
    ON us.user_id = iu.investor_id
  WHERE iu.project_id = NEW.project_id
    -- Soft-deleted allocations must not be notified. (Note:
    -- gallery-sync and documents-sync do NOT filter this today, so they
    -- will still notify withdrawn investors — separate bug, not fixed
    -- here.)
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.investor_id            = iu.investor_id
        AND n.type                   = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
    );

  GET DIAGNOSTICS v_notified = ROW_COUNT;
  RAISE LOG 'notify_project_phase_change: project=% stage=% (%) notified=%',
    NEW.project_id, NEW.sort_order, v_stage_label, v_notified;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_project_phase_change() IS
  'Fans out an in-app phase_update notification to every investor '
  'holding units in the project when a project_phases row becomes '
  'current. Idempotent per (investor, project, stage_index). '
  'Honours user_settings.notifications_enabled.';

DROP TRIGGER IF EXISTS trg_notify_project_phase_change
  ON public.project_phases;

CREATE TRIGGER trg_notify_project_phase_change
  AFTER INSERT OR UPDATE OF status ON public.project_phases
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_project_phase_change();

-- ------------------------------------------------------------
-- 2) Match migration 060: SECURITY DEFINER functions must not be
--    callable over PostgREST as /rest/v1/rpc/<name>. Trigger
--    execution ignores the caller's EXECUTE grant, so revoking
--    here has no functional impact.
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.notify_project_phase_change()
  FROM public, anon, authenticated;

-- ------------------------------------------------------------
-- 3) Supporting index for the idempotency probe. Without it the
--    NOT EXISTS above degrades to a seq scan on notifications
--    once the feed grows.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_notifications_phase_update_dedupe
  ON public.notifications (
    investor_id,
    (metadata ->> 'project_id'),
    (metadata ->> 'stage_index')
  )
  WHERE type = 'phase_update';
