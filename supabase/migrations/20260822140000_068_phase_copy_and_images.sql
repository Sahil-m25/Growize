-- ============================================================
-- MIGRATION 068 — HUMAN COPY + IMAGES FOR PHASE NOTIFICATIONS
--
-- 066 and 067 echoed the Zoho stage label straight at investors:
--   "Stage complete: Land Closed"
--   "EKA LLP has completed the Land Closed stage."
-- "Land Closed" is an internal taxonomy name, not news. Compare the
-- Growize Farms LinkedIn post for the same event — a bhoomi puja on
-- site, two warm lines, photos. That is the register investors expect.
--
-- This migration adds:
--   1. project_phases.image_url — one photo per stage.
--   2. public.phase_copy — an EDITABLE table of per-stage wording, so
--      changing what investors read is an UPDATE, not a migration.
--      Ops owns the words; engineering owns the plumbing.
--   3. A rewritten trigger that reads both.
--
-- Copy below is a DRAFT written from the stage taxonomy alone. It
-- deliberately restates what each milestone means and does NOT invent
-- operational specifics (no "borewell commissioned", no acreage, no
-- dates) — those would be claims nobody verified. Edit freely:
--   UPDATE public.phase_copy SET completed_body = '...' WHERE stage_index = 0;
-- ============================================================

ALTER TABLE public.project_phases
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.project_phases.image_url IS
  'Optional photo for this milestone. Rendered as a banner in the '
  'in-app notification card. Must be a publicly reachable URL — the '
  'arl-gallery bucket is private and its signed URLs expire, so use a '
  'public bucket or CDN.';

-- ------------------------------------------------------------
-- Per-stage wording. {project} is substituted with the project name.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_copy (
  stage_index     INT PRIMARY KEY CHECK (stage_index BETWEEN 0 AND 9),
  milestone_title TEXT NOT NULL,
  started_body    TEXT NOT NULL,
  completed_body  TEXT NOT NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.phase_copy IS
  'Investor-facing wording per stage. Edit these rows to change what '
  'notifications say — no migration needed. {project} is replaced with '
  'the project name at send time.';

-- Bodies are kept to ~70 characters so they render as TWO lines in the
-- notification card at 390px. Verified against a real render: the first
-- draft ran to three lines and was cut down.
INSERT INTO public.phase_copy (stage_index, milestone_title, started_body, completed_body) VALUES
  (0, 'Land acquired',
      '{project} has begun securing its site. Updates to follow.',
      '{project}''s land is secured and registered. Design and planning are next.'),
  (1, 'Design locked',
      'Design and planning for {project} are underway.',
      'The layout for {project} is approved. Site preparation is next.'),
  (2, 'Site prepared',
      'Site preparation has started at {project}.',
      'Ground work at {project} is done. Core civil work is next.'),
  (3, 'Civil work complete',
      'Core civil work has begun at {project}.',
      'Foundations at {project} are complete. Procurement is next.'),
  (4, 'Procurement locked',
      'Procurement for {project} is underway.',
      'Equipment for {project} is confirmed. Water systems are next.'),
  (5, 'Water systems ready',
      'Water and storage work has started at {project}.',
      'Water and storage at {project} are ready. Power is next.'),
  (6, 'Power connected',
      'Power connection work has started at {project}.',
      '{project} now has its power connection. The greenhouse is next.'),
  (7, 'Greenhouse built',
      'Greenhouse construction has begun at {project}.',
      'The greenhouse at {project} is built. Production systems are next.'),
  (8, 'Systems installed',
      'Production systems are going in at {project}.',
      'Production systems at {project} are in. Final compliance is last.'),
  (9, 'Now live',
      'Final compliance work has started at {project}.',
      '{project} has cleared compliance and is live. Thank you for backing it.')
ON CONFLICT (stage_index) DO NOTHING;

ALTER TABLE public.phase_copy ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "phase_copy: readable by signed-in users" ON public.phase_copy;
CREATE POLICY "phase_copy: readable by signed-in users"
  ON public.phase_copy FOR SELECT TO authenticated USING (true);

-- ------------------------------------------------------------
-- Trigger — same fan-out and guards as 067, new wording + image.
-- ------------------------------------------------------------
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
  v_copy         public.phase_copy%ROWTYPE;
  v_title        TEXT;
  v_body         TEXT;
  v_meta         JSONB;
  v_notified     INT;
BEGIN
  IF NEW.status = 'current'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'current') THEN
    v_kind := 'started';
  ELSIF NEW.status = 'done'
        AND TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM 'done' THEN
    v_kind := 'completed';        -- backfill guard: UPDATE only
  ELSE
    RETURN NEW;
  END IF;

  SELECT p.name INTO v_project_name
  FROM public.projects p
  WHERE p.id = NEW.project_id AND p.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  v_stage_label := COALESCE(NULLIF(TRIM(NEW.phase_name), ''), 'a new stage');

  SELECT * INTO v_copy FROM public.phase_copy WHERE stage_index = NEW.sort_order;

  IF FOUND THEN
    v_title := v_copy.milestone_title;
    v_body  := REPLACE(
                 CASE WHEN v_kind = 'started'
                      THEN v_copy.started_body
                      ELSE v_copy.completed_body END,
                 '{project}', COALESCE(v_project_name, 'Your project'));
  ELSE
    -- No copy row for this stage — fall back to the 067 wording rather
    -- than sending an empty card.
    IF v_kind = 'started' THEN
      v_title := 'Stage update: ' || v_stage_label;
      v_body  := COALESCE(v_project_name, 'Your project')
                 || ' has moved to ' || v_stage_label || '.';
    ELSE
      v_title := 'Stage complete: ' || v_stage_label;
      v_body  := COALESCE(v_project_name, 'Your project')
                 || ' has completed the ' || v_stage_label || ' stage.';
    END IF;
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

  -- Only carry image_url when there actually is one; an absent key is
  -- cleaner for the client than a null.
  IF NEW.image_url IS NOT NULL AND TRIM(NEW.image_url) <> '' THEN
    v_meta := v_meta || jsonb_build_object('image_url', NEW.image_url);
  END IF;

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT DISTINCT
         iu.investor_id, 'phase_update', v_title, v_body, v_meta
  FROM public.investor_units iu
  LEFT JOIN public.user_settings us ON us.user_id = iu.investor_id
  WHERE iu.project_id = NEW.project_id
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.investor_id              = iu.investor_id
        AND n.type                     = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
        AND n.metadata ->> 'kind'        = v_kind
    );

  GET DIAGNOSTICS v_notified = ROW_COUNT;
  RAISE LOG 'notify_project_phase_change: project=% stage=% kind=% notified=%',
    NEW.project_id, NEW.sort_order, v_kind, v_notified;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_project_phase_change ON public.project_phases;
CREATE TRIGGER trg_notify_project_phase_change
  AFTER INSERT OR UPDATE OF status ON public.project_phases
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_project_phase_change();

REVOKE EXECUTE ON FUNCTION public.notify_project_phase_change()
  FROM public, anon, authenticated;
