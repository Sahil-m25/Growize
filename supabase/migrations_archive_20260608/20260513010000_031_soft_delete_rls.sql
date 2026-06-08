-- ============================================================
-- MIGRATION 031 — SOFT-DELETE RLS PROPAGATION
-- Adds `deleted_at IS NULL` to the existing authenticated SELECT
-- policies on investors and projects so soft-deleted rows
-- vanish from app reads without needing a hard DELETE.
-- Also adds a defensive SELECT policy on `llps` (no app reads
-- today, but enforces the same active-row contract should the
-- marketplace surface LLP-level metadata later).
--
-- Postgres does not allow ALTER POLICY ... USING (...) on an
-- existing policy expression — we DROP + CREATE with the
-- updated predicate. Service-role writes bypass RLS, so the
-- zoho-crm-webhook can still update + soft-delete rows freely.
--
-- The `projects_public` view referenced in the original spec
-- does not exist in this codebase (no migration creates it,
-- no app code references it). Filtering happens at the
-- table-policy layer instead; if/when projects_public is
-- introduced, its underlying SELECT must inherit the
-- `deleted_at IS NULL` predicate.
-- ============================================================

-- investors: read own active row only ----------------------------
DROP POLICY IF EXISTS "investors: read own row" ON public.investors;
CREATE POLICY "investors: read own row"
  ON public.investors FOR SELECT
  TO authenticated
  USING (
    id = (SELECT auth.uid())
    AND deleted_at IS NULL
  );

-- projects: marketplace OR owned-units, active only --------------
DROP POLICY IF EXISTS "projects: visible to investors with units OR marketplace"
  ON public.projects;
CREATE POLICY "projects: visible to investors with units OR marketplace"
  ON public.projects FOR SELECT
  TO authenticated
  USING (
    deleted_at IS NULL
    AND (
      is_listed_in_marketplace = true
      OR id IN (
        SELECT investor_units.project_id
        FROM public.investor_units
        WHERE investor_units.investor_id = (SELECT auth.uid())
      )
    )
  );

-- llps: defensive policy. RLS may or may not be enabled today;
-- enable it idempotently then install a select policy that
-- mirrors `projects` (visible when the investor has units in
-- one of the LLP's projects) AND respects deleted_at.
ALTER TABLE public.llps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "llps: visible via owned projects" ON public.llps;
CREATE POLICY "llps: visible via owned projects"
  ON public.llps FOR SELECT
  TO authenticated
  USING (
    deleted_at IS NULL
    AND id IN (
      SELECT p.llp_id
      FROM public.projects p
      JOIN public.investor_units iu ON iu.project_id = p.id
      WHERE iu.investor_id = (SELECT auth.uid())
        AND p.deleted_at IS NULL
    )
  );

COMMENT ON POLICY "investors: read own row" ON public.investors IS
  'Own row + active (deleted_at IS NULL). Soft-deleted CRM rows are hidden.';
COMMENT ON POLICY "projects: visible to investors with units OR marketplace" ON public.projects IS
  'Marketplace listings OR own-units, active only. Soft-deleted CRM rows hidden.';
COMMENT ON POLICY "llps: visible via owned projects" ON public.llps IS
  'Visible only via an active linked project the investor owns units in. Soft-deleted hidden.';
