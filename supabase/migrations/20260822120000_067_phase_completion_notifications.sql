-- ============================================================
-- MIGRATION 067 — PHASE *COMPLETION* NOTIFICATIONS
--
-- Extends migration 066. That version only spoke when a stage
-- became `current` ("EKA LLP has moved to Site Prep."). It had
-- nothing to say when a stage was signed off, which is the more
-- meaningful investor event — "the land is acquired" is a
-- completion, not a start.
--
-- After this migration the trigger emits two distinct events:
--
--   status -> 'current'   "Stage update: <stage>"
--                         "<project> has moved to <stage>."
--                         metadata.kind = 'started'
--
--   status -> 'done'      "Stage complete: <stage>"
--                         "<project> has completed the <stage> stage."
--                         metadata.kind = 'completed'
--
-- ------------------------------------------------------------
-- Two behaviours worth understanding before you edit this:
--
-- 1. BACKFILL GUARD. `done` fires on UPDATE only, never on
--    INSERT. Seeding a project's history — inserting stages 0-4
--    already marked done — is a data-loading operation, not five
--    things that just happened, and firing there would drop five
--    notifications into every investor's feed at once. A stage
--    that genuinely completes does so as an UPDATE of an existing
--    row. `current` still fires on INSERT as well, because the
--    first Zoho sync landing an already-in-progress stage IS news
--    and is at most one notification.
--
-- 2. DEDUPE KEY NOW INCLUDES `kind`. Under 066 the key was
--    (investor, project, stage_index). A stage moving
--    current -> done would have been swallowed, because a row for
--    that stage already existed. The key is now
--    (investor, project, stage_index, kind) so each stage can
--    produce at most one "started" and one "completed" per
--    investor, and replays of either are still ignored.
--
-- Verified against production 2026-08-22 (ref oynfhdqizebvgmaoiuax):
-- `notifications` held ZERO rows of type phase_update at the time
-- this was written, so there is no historical data to migrate to
-- the new metadata shape.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_project_phase_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_kind         TEXT;
  v_project_name TEXT;
  v_stage_label  TEXT;
  v_title        TEXT;
  v_body         TEXT;
  v_meta         JSONB;
  v_notified     INT;
BEGIN
  -- Classify the transition. Anything else is not newsworthy.
  IF NEW.status = 'current'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'current') THEN
    v_kind := 'started';
  ELSIF NEW.status = 'done'
        AND TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM 'done' THEN
    v_kind := 'completed';          -- see BACKFILL GUARD above
  ELSE
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

  IF v_kind = 'started' THEN
    v_title := 'Stage update: ' || v_stage_label;
    v_body  := COALESCE(v_project_name, 'Your project')
               || ' has moved to ' || v_stage_label || '.';
  ELSE
    v_title := 'Stage complete: ' || v_stage_label;
    v_body  := COALESCE(v_project_name, 'Your project')
               || ' has completed the ' || v_stage_label || ' stage.';
  END IF;

  v_meta := jsonb_build_object(
    'project_id',   NEW.project_id,
    'project_name', v_project_name,
    'stage_index',  NEW.sort_order,
    'phase_name',   NEW.phase_name,
    'kind',         v_kind,
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
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.investor_id             = iu.investor_id
        AND n.type                    = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
        AND n.metadata ->> 'kind'        = v_kind
    );

  GET DIAGNOSTICS v_notified = ROW_COUNT;
  RAISE LOG 'notify_project_phase_change: project=% stage=% (%) kind=% notified=%',
    NEW.project_id, NEW.sort_order, v_stage_label, v_kind, v_notified;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_project_phase_change() IS
  'Fans out in-app phase_update notifications to every investor holding '
  'units in the project. Emits kind=started when a stage becomes current '
  'and kind=completed when one is signed off (UPDATE only — inserting an '
  'already-done row is treated as a backfill and stays silent). '
  'Idempotent per (investor, project, stage_index, kind). '
  'Honours user_settings.notifications_enabled.';

-- Trigger definition is unchanged from 066 (AFTER INSERT OR UPDATE OF
-- status) — it already delivers `done` transitions, 066 just ignored
-- them. Re-asserted here so this file stands alone.
DROP TRIGGER IF EXISTS trg_notify_project_phase_change
  ON public.project_phases;

CREATE TRIGGER trg_notify_project_phase_change
  AFTER INSERT OR UPDATE OF status ON public.project_phases
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_project_phase_change();

REVOKE EXECUTE ON FUNCTION public.notify_project_phase_change()
  FROM public, anon, authenticated;

-- Dedupe index gains `kind` to match the widened key.
DROP INDEX IF EXISTS public.idx_notifications_phase_update_dedupe;
CREATE INDEX IF NOT EXISTS idx_notifications_phase_update_dedupe
  ON public.notifications (
    investor_id,
    (metadata ->> 'project_id'),
    (metadata ->> 'stage_index'),
    (metadata ->> 'kind')
  )
  WHERE type = 'phase_update';
