-- ============================================================
-- 042: Soft-delete column on investor_units (DEF-10)
-- ============================================================
-- Follows the soft-delete pattern of migrations 037-038: cancelled
-- allocations are marked, not removed, so that FK references from
-- payouts / exit_requests and historical reporting stay intact.
-- ============================================================

ALTER TABLE public.investor_units
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.investor_units.deleted_at IS
  'NULL = active. Set when allocation is cancelled; row stays for FK integrity + payout audit.';

CREATE INDEX IF NOT EXISTS idx_investor_units_deleted_at
  ON public.investor_units (deleted_at)
  WHERE deleted_at IS NOT NULL;

-- ------------------------------------------------------------
-- RLS: hide soft-deleted rows from the owner-facing SELECT policy
-- (created in migration 009). Drop + recreate to amend the USING
-- clause; the policy still scopes to the investor's own rows.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "investor_units: read own rows" ON public.investor_units;

CREATE POLICY "investor_units: read own rows"
  ON public.investor_units FOR SELECT
  TO authenticated
  USING (
    investor_id = (SELECT auth.uid())
    AND deleted_at IS NULL
  );
