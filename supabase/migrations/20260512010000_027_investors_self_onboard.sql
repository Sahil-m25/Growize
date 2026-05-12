-- ============================================================
-- MIGRATION 027 — INVESTORS SELF-ONBOARD WRITES
-- Lets a freshly signed-up auth user create or update their own
-- investors row from InitialSetupScreen. Previously the table was
-- write-protected for the authenticated role (service_role only),
-- since rows were created exclusively by the Zoho CRM webhook /
-- onboard-investor Edge Function.
--
-- Changes:
--   1) arl_id becomes nullable — self-onboarded rows don't have an
--      ARL-issued contact ID until staff assigns one. Existing
--      staff-invited rows keep theirs untouched.
--   2) RLS INSERT and UPDATE policies for own row (id = auth.uid()).
--   3) GRANT INSERT, UPDATE on public.investors to authenticated.
-- ============================================================

-- 1) Allow self-onboarded rows without an arl_id ---------------
ALTER TABLE public.investors ALTER COLUMN arl_id DROP NOT NULL;

COMMENT ON COLUMN public.investors.arl_id IS
  'ARL-issued contact ID. NULL for self-onboarded rows until ARL ops '
  'assigns one (staff-invited rows still have it from Zoho).';

-- 2) RLS policies for self-onboard write -----------------------
CREATE POLICY "investors: insert own row"
  ON public.investors FOR INSERT
  TO authenticated
  WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY "investors: update own row"
  ON public.investors FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

-- 3) Grants ----------------------------------------------------
GRANT INSERT, UPDATE ON public.investors TO authenticated;
