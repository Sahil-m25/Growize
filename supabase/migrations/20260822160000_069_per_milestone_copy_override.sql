-- ============================================================
-- MIGRATION 069 — PER-MILESTONE COPY OVERRIDE
--
-- 068 gave every stage editable wording via public.phase_copy. That
-- table is keyed by stage_index ALONE, so a row there speaks for that
-- stage on EVERY project, forever.
--
-- Which is wrong for anything time-bound or project-specific. "We begin
-- construction next month" is true of Eka in August 2026 and false of
-- the next project that closes its land, and false of Eka itself once
-- next month arrives. Writing it into phase_copy would quietly turn
-- into a lie told to investors.
--
-- So: per-row overrides on project_phases. phase_copy keeps the
-- durable, generic wording; these columns carry the bespoke line for
-- one milestone on one project. Resolution order in the trigger:
--
--   project_phases.custom_title / custom_body   (this milestone only)
--   -> public.phase_copy                        (this stage, all projects)
--   -> the 067 generic fallback                 (never an empty card)
--
-- {project} is substituted in overrides too, so a bespoke line can
-- still name the project without hardcoding it.
-- ============================================================

ALTER TABLE public.project_phases
  ADD COLUMN IF NOT EXISTS custom_title TEXT,
  ADD COLUMN IF NOT EXISTS custom_body  TEXT;

COMMENT ON COLUMN public.project_phases.custom_title IS
  'Overrides phase_copy.milestone_title for THIS milestone only. Use for '
  'wording that is specific to one project or one moment in time.';
COMMENT ON COLUMN public.project_phases.custom_body IS
  'Overrides phase_copy started_body/completed_body for THIS milestone '
  'only. Keep near 70 characters so it renders as two lines. {project} '
  'is substituted. Anything time-bound ("next month") belongs here, not '
  'in phase_copy.';

CREATE OR REPLACE FUNCTION public.notify_project_phase_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_kind TEXT; v_project_name TEXT; v_stage_label TEXT;
  v_copy public.phase_copy%ROWTYPE;
  v_title TEXT; v_body TEXT; v_meta JSONB; v_notified INT;
BEGIN
  IF NEW.status = 'current'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'current') THEN
    v_kind := 'started';
  ELSIF NEW.status = 'done'
        AND TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM 'done' THEN
    v_kind := 'completed';
  ELSE
    RETURN NEW;
  END IF;

  SELECT p.name INTO v_project_name FROM public.projects p
  WHERE p.id = NEW.project_id AND p.deleted_at IS NULL;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_stage_label := COALESCE(NULLIF(TRIM(NEW.phase_name), ''), 'a new stage');
  SELECT * INTO v_copy FROM public.phase_copy WHERE stage_index = NEW.sort_order;

  -- 2) stage-level copy, or 3) generic fallback
  IF FOUND THEN
    v_title := v_copy.milestone_title;
    v_body  := CASE WHEN v_kind = 'started'
                    THEN v_copy.started_body
                    ELSE v_copy.completed_body END;
  ELSE
    IF v_kind = 'started' THEN
      v_title := 'Stage update: ' || v_stage_label;
      v_body  := '{project} has moved to ' || v_stage_label || '.';
    ELSE
      v_title := 'Stage complete: ' || v_stage_label;
      v_body  := '{project} has completed the ' || v_stage_label || ' stage.';
    END IF;
  END IF;

  -- 1) per-milestone override wins over both.
  IF NEW.custom_title IS NOT NULL AND TRIM(NEW.custom_title) <> '' THEN
    v_title := NEW.custom_title;
  END IF;
  IF NEW.custom_body IS NOT NULL AND TRIM(NEW.custom_body) <> '' THEN
    v_body := NEW.custom_body;
  END IF;

  v_body := REPLACE(v_body, '{project}',
                    COALESCE(v_project_name, 'Your project'));

  v_meta := jsonb_build_object(
    'project_id', NEW.project_id, 'project_name', v_project_name,
    'stage_index', NEW.sort_order, 'phase_name', NEW.phase_name,
    'kind', v_kind,
    'cta_route', '/projects/' || NEW.project_id::TEXT,
    'cta_label', 'View Project');

  IF NEW.image_url IS NOT NULL AND TRIM(NEW.image_url) <> '' THEN
    v_meta := v_meta || jsonb_build_object('image_url', NEW.image_url);
  END IF;

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT DISTINCT iu.investor_id, 'phase_update', v_title, v_body, v_meta
  FROM public.investor_units iu
  LEFT JOIN public.user_settings us ON us.user_id = iu.investor_id
  WHERE iu.project_id = NEW.project_id
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.investor_id = iu.investor_id AND n.type = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
        AND n.metadata ->> 'kind'        = v_kind);

  GET DIAGNOSTICS v_notified = ROW_COUNT;
  RAISE LOG 'notify_project_phase_change: project=% stage=% kind=% notified=%',
    NEW.project_id, NEW.sort_order, v_kind, v_notified;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_project_phase_change ON public.project_phases;
CREATE TRIGGER trg_notify_project_phase_change
  AFTER INSERT OR UPDATE OF status ON public.project_phases
  FOR EACH ROW EXECUTE FUNCTION public.notify_project_phase_change();

REVOKE EXECUTE ON FUNCTION public.notify_project_phase_change()
  FROM public, anon, authenticated;
