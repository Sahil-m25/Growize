-- 073: dedicated titles for "stage started" updates.
-- Before this, a stage that had just started reused the milestone
-- (completed) title, e.g. "Civil work complete" when civil work began.
-- Applied live on 2026-09-27.

ALTER TABLE public.phase_copy ADD COLUMN IF NOT EXISTS started_title TEXT;

UPDATE public.phase_copy AS pc SET started_title = v.t
FROM (VALUES
  (0, 'Site search underway'),
  (1, 'Design underway'),
  (2, 'Site preparation begins'),
  (3, 'Civil work begins'),
  (4, 'Procurement underway'),
  (5, 'Water works begin'),
  (6, 'Power work begins'),
  (7, 'Greenhouse construction begins'),
  (8, 'Systems installation begins'),
  (9, 'Final compliance underway')
) AS v(i, t)
WHERE pc.stage_index = v.i;

CREATE OR REPLACE FUNCTION public.resolve_phase_copy(p_phase project_phases, p_kind text, p_project_name text)
 RETURNS TABLE(title text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_copy public.phase_copy%ROWTYPE; v_label TEXT; v_title TEXT; v_body TEXT;
BEGIN
  v_label := COALESCE(NULLIF(TRIM(p_phase.phase_name), ''), 'a new stage');
  SELECT * INTO v_copy FROM public.phase_copy WHERE stage_index = p_phase.sort_order;
  IF FOUND THEN
    v_title := CASE WHEN p_kind='started'
                    THEN COALESCE(NULLIF(TRIM(v_copy.started_title), ''), 'Underway: ' || v_label)
                    ELSE v_copy.milestone_title END;
    v_body  := CASE WHEN p_kind='started' THEN v_copy.started_body ELSE v_copy.completed_body END;
  ELSE
    IF p_kind='started' THEN
      v_title := 'Stage update: ' || v_label;
      v_body  := '{project} has moved to ' || v_label || '.';
    ELSE
      v_title := 'Stage complete: ' || v_label;
      v_body  := '{project} has completed the ' || v_label || ' stage.';
    END IF;
  END IF;
  IF p_phase.custom_title IS NOT NULL AND TRIM(p_phase.custom_title) <> '' THEN
    v_title := p_phase.custom_title; END IF;
  IF p_phase.custom_body IS NOT NULL AND TRIM(p_phase.custom_body) <> '' THEN
    v_body := p_phase.custom_body; END IF;
  RETURN QUERY SELECT v_title,
    REPLACE(v_body,'{project}',COALESCE(p_project_name,'Your project'));
END $function$;

REVOKE EXECUTE ON FUNCTION public.resolve_phase_copy(project_phases, text, text) FROM PUBLIC, anon, authenticated;
