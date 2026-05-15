-- ============================================================
-- MIGRATION 046 — Make projects.units_issued + units_available
-- derived from investor_units; add non-negativity CHECK.
--
-- Resolves:
--   * DEF-2026-05-15-01 (Sample Test LLP units_available = -30,
--     no CHECK guards Zoho payloads that violate the invariant).
--   * DEF-2026-05-15-05 (5-project drift between projects.units_issued
--     and SUM(investor_units.issued_units) — cards under-report).
--
-- Architecture call:
--   `total_units` remains Zoho-sourced (the LLP-level "how many
--   units exist" figure). `units_issued` is recomputed by a
--   trigger as SUM(investor_units.issued_units WHERE deleted_at
--   IS NULL AND allocation_status = 'Issued') for each project.
--   `units_available` is then GREATEST(total_units - units_issued, 0).
--   The Zoho webhook stops writing these two columns (see
--   supabase/functions/zoho-crm-webhook/index.ts).
--
-- Postgres note: GENERATED ALWAYS AS columns cannot aggregate
-- across tables, so the same semantics ("derived data only") are
-- implemented via a trigger on investor_units that recomputes
-- the parent project row whenever an allocation changes. From
-- the caller's perspective the columns behave as if generated.
-- ============================================================

-- 1) Clean the offending Sample Test LLP row before adding the CHECK.
-- Per spec: set units_available to 0 if total_units >= units_issued.
-- The Sample Test LLP row has Zoho-input units_issued=50, total=20,
-- units_available=-30 — total_units < units_issued, so we null out
-- the operational fields and tag the project_name for ops cleanup.
UPDATE public.projects
   SET units_available = 0
 WHERE units_available < 0
   AND total_units >= units_issued;

UPDATE public.projects
   SET units_issued    = 0,
       units_available = 0,
       name = name || ' [ops: needs cleanup — invalid Zoho payload 046]'
 WHERE units_available < 0
    OR units_issued > total_units;

-- 2) Recompute function. Used by the trigger below + the backfill
-- loop. SECURITY DEFINER so triggers fired under the anon role
-- can still update projects rows (RLS on projects denies anon
-- writes).
CREATE OR REPLACE FUNCTION public.recompute_project_units(p_project_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_issued NUMERIC;
  v_total  NUMERIC;
BEGIN
  IF p_project_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(issued_units), 0)
    INTO v_issued
    FROM public.investor_units
   WHERE project_id = p_project_id
     AND deleted_at IS NULL
     AND allocation_status = 'Issued';

  SELECT COALESCE(total_units, 0)
    INTO v_total
    FROM public.projects
   WHERE id = p_project_id;

  UPDATE public.projects
     SET units_issued    = v_issued,
         units_available = GREATEST(v_total - v_issued, 0)
   WHERE id = p_project_id;
END;
$$;

COMMENT ON FUNCTION public.recompute_project_units(UUID) IS
  'Recomputes projects.units_issued + projects.units_available from '
  'investor_units (active + allocation_status=Issued). Source of '
  'truth lives in investor_units; this fn is the sync path.';

-- 3) Trigger on investor_units fires the recompute on any change.
CREATE OR REPLACE FUNCTION public.trg_recompute_project_units_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_project_units(OLD.project_id);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE'
        AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
    PERFORM public.recompute_project_units(OLD.project_id);
    PERFORM public.recompute_project_units(NEW.project_id);
    RETURN NEW;
  ELSE
    PERFORM public.recompute_project_units(NEW.project_id);
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_project_units
  ON public.investor_units;
CREATE TRIGGER trg_recompute_project_units
  AFTER INSERT OR UPDATE OR DELETE ON public.investor_units
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_project_units_fn();

-- 4) One-shot backfill: every project recomputes from its current
-- investor_units rows. Rows with no Issued allocations get
-- units_issued=0 and units_available=total_units (or 0 if total
-- is NULL). This is the post-046 source of truth.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.projects WHERE deleted_at IS NULL LOOP
    PERFORM public.recompute_project_units(r.id);
  END LOOP;
END;
$$;

-- 5) CHECK constraints — applied AFTER backfill so the invariant
-- holds for every existing row. Future writes that violate them
-- (whether from Zoho payloads or hand-edits in Studio) get
-- rejected at write time and surface in webhook_log.error_message.
ALTER TABLE public.projects
  ADD CONSTRAINT projects_units_nonneg
  CHECK (
    units_available >= 0
    AND units_issued >= 0
    AND units_issued <= COALESCE(total_units, units_issued)
  );

-- Rollback:
--   ALTER TABLE public.projects DROP CONSTRAINT projects_units_nonneg;
--   DROP TRIGGER trg_recompute_project_units ON public.investor_units;
--   DROP FUNCTION public.trg_recompute_project_units_fn();
--   DROP FUNCTION public.recompute_project_units(UUID);
--   -- Restore previous values from a snapshot if needed.
