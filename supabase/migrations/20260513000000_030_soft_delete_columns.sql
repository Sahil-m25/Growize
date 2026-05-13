-- ============================================================
-- MIGRATION 030 — SOFT-DELETE COLUMNS
-- Adds `deleted_at TIMESTAMPTZ` to the three CRM-mirrored tables
-- so the zoho-crm-webhook can mark rows deleted in the upstream
-- CRM without breaking FK integrity (investor_units, payouts,
-- documents, etc. keep their parent rows for audit + history).
--
-- Conventions:
--   * NULL  = active row (default)
--   * NOT NULL = row was deleted upstream at this timestamp;
--                hidden by RLS (migration 031) and ignored by
--                the app's repository layer (defense in depth).
--
-- Reads stay cheap: each table gets a partial index on
-- (deleted_at) WHERE deleted_at IS NOT NULL so the small
-- soft-deleted slice is scannable for ops queries without
-- bloating the hot active-row indexes.
-- ============================================================

-- investors -----------------------------------------------------
ALTER TABLE public.investors
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.investors.deleted_at IS
  'NULL = active. Set when source CRM record is deleted; row stays for FK integrity + audit.';

CREATE INDEX IF NOT EXISTS idx_investors_deleted_at
  ON public.investors (deleted_at)
  WHERE deleted_at IS NOT NULL;

-- llps ----------------------------------------------------------
ALTER TABLE public.llps
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.llps.deleted_at IS
  'NULL = active. Set when source CRM record is deleted; row stays for FK integrity + audit.';

CREATE INDEX IF NOT EXISTS idx_llps_deleted_at
  ON public.llps (deleted_at)
  WHERE deleted_at IS NOT NULL;

-- projects ------------------------------------------------------
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.projects.deleted_at IS
  'NULL = active. Set when source CRM record is deleted; row stays for FK integrity + audit.';

CREATE INDEX IF NOT EXISTS idx_projects_deleted_at
  ON public.projects (deleted_at)
  WHERE deleted_at IS NOT NULL;
