-- Migration 021: Combine projects SELECT policies
-- DROP both separate marketplace and investor-units policies
-- CREATE one combined policy with OR condition

DROP POLICY IF EXISTS "projects: marketplace listings visible to authenticated" ON public.projects;
DROP POLICY IF EXISTS "projects: visible to investors with units" ON public.projects;

CREATE POLICY "projects: visible to investors with units OR marketplace"
  ON public.projects FOR SELECT
  TO authenticated
  USING (
    is_listed_in_marketplace = true
    OR id IN (
      SELECT investor_units.project_id
      FROM investor_units
      WHERE investor_units.investor_id = (SELECT auth.uid())
    )
  );
