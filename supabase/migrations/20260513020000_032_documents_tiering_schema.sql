-- ============================================================
-- MIGRATION 032 — DOCUMENT TIERING SCHEMA
-- Splits documents into three visibility tiers:
--   * common   — visible to every authenticated investor
--                (e.g. company prospectus, sample agreement,
--                 brand-wide compliance documents)
--   * project  — visible to investors who have units in the
--                referenced project (e.g. project-specific
--                land deeds, crop reports)
--   * investor — visible only to a single investor
--                (e.g. their own contracts, KYC packets) —
--                the existing default, the legacy contract
--
-- Backfill: every existing row has investor_id set, so the
-- DEFAULT 'investor' value is correct without an UPDATE
-- statement.
-- ============================================================

-- 1) visibility tier column ------------------------------------
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'investor'
    CHECK (visibility IN ('common', 'project', 'investor'));

COMMENT ON COLUMN public.documents.visibility IS
  'Tier: common=all authenticated, project=units-in-project, investor=own only.';

-- 2) project_id FK (SET NULL on delete so soft-delete or hard-
--    delete of the project doesn''t orphan-cascade the document)
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS project_id UUID
    REFERENCES public.projects(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.documents.project_id IS
  'Required when visibility=project; NULL for common/investor tiers.';

-- 3) investor_id becomes nullable -------------------------------
-- Common + project-tier rows have NULL investor_id. The CHECK
-- below enforces the tier <-> column-presence invariant so the
-- legacy schema constraint (investor_id NOT NULL) gracefully
-- relaxes to the new contract.
ALTER TABLE public.documents
  ALTER COLUMN investor_id DROP NOT NULL;

-- 4) tier invariant CHECK ---------------------------------------
-- common   → investor_id IS NULL AND project_id IS NULL
-- project  → investor_id IS NULL AND project_id IS NOT NULL
-- investor → investor_id IS NOT NULL
ALTER TABLE public.documents
  ADD CONSTRAINT documents_tier_columns_check CHECK (
    (visibility = 'common'   AND investor_id IS NULL     AND project_id IS NULL)     OR
    (visibility = 'project'  AND investor_id IS NULL     AND project_id IS NOT NULL) OR
    (visibility = 'investor' AND investor_id IS NOT NULL)
  );

-- 5) helpful indexes for the new tiers --------------------------
CREATE INDEX IF NOT EXISTS idx_documents_visibility
  ON public.documents (visibility, uploaded_at DESC);

CREATE INDEX IF NOT EXISTS idx_documents_project
  ON public.documents (project_id, uploaded_at DESC)
  WHERE project_id IS NOT NULL;
