-- ============================================================
-- MIGRATION 045 — Two ops-hygiene fixes surfaced by the
-- 2026-05-15 ops-doc consolidation pass.
--
-- (A) DEF-OPS-2: exit-request approved -> settled does not fire
--     a notification. The trigger was gated on
--     OLD.status='pending', so the natural ops flow
--     (pending -> approved -> settled) silenced the "settled"
--     bell. Widen the gate: fire whenever NEW.status is a
--     terminal value AND it is actually changing. The body is
--     already keyed on NEW.status, so path-independence is the
--     correct semantic.
--
-- (B) DEF-MKT-03: projects.units_issued and projects.units_available
--     can be NULL on rows where the Zoho LLP_Creation_Module
--     never sent Total_Issued_Units. Default both to 0,
--     backfill the three existing NULL rows. This is purely
--     hygiene; the Zoho webhook continues to UPSERT these
--     columns from Zoho's authoritative values.
-- ============================================================

-- (A) Replace the function. Trigger binding is preserved.
CREATE OR REPLACE FUNCTION public.notify_exit_request_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_title TEXT; v_body TEXT;
BEGIN
  -- Fire for any transition INTO a terminal state, regardless
  -- of the prior state. Handles pending -> approved -> settled.
  IF NEW.status IN ('approved', 'rejected', 'settled')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'approved' THEN v_title := 'Exit request approved'; v_body := 'Your exit request has been approved. Settlement will follow.';
      WHEN 'rejected' THEN v_title := 'Exit request rejected'; v_body := 'Your exit request has been rejected. Reach out to support for details.';
      ELSE                  v_title := 'Exit settled';         v_body := 'Your exit settlement has been processed.';
    END CASE;
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.user_id, 'exit', v_title, v_body,
      jsonb_build_object('exit_request_id', NEW.id, 'status', NEW.status, 'investor_unit_id', NEW.investor_unit_id)
    );
  END IF;
  RETURN NEW;
END;
$$;

-- (B) Column defaults + backfill.
ALTER TABLE public.projects
  ALTER COLUMN units_issued    SET DEFAULT 0;
ALTER TABLE public.projects
  ALTER COLUMN units_available SET DEFAULT 0;

UPDATE public.projects
   SET units_issued = 0
 WHERE units_issued IS NULL;

UPDATE public.projects
   SET units_available = GREATEST(COALESCE(total_units, 0) - COALESCE(units_issued, 0), 0)
 WHERE units_available IS NULL;

-- Rollback:
--   ALTER TABLE public.projects ALTER COLUMN units_issued    DROP DEFAULT;
--   ALTER TABLE public.projects ALTER COLUMN units_available DROP DEFAULT;
--   (NULL backfill is one-way; restore from a prior snapshot if needed.)
--   And restore the prior notify_exit_request_status_change() function
--   from migration 034.
