-- ============================================================
-- MIGRATION 033 — DOCUMENT TIERING RLS + STORAGE
-- Rewrites the documents SELECT policy + matching storage RLS
-- so the three tiers introduced in migration 032 produce the
-- right read scope per investor.
--
-- INSERT is investor-only — they can only attach a personal
-- (visibility=investor, investor_id=auth.uid()) document via
-- the app. Ops-uploaded common + project documents go in via
-- service_role (Supabase Studio or an Edge Function), which
-- bypasses RLS.
--
-- Storage paths mirror the DB tiers:
--   documents/common/<file>
--   documents/project/<project_id>/<file>
--   documents/investor/<auth.uid()>/<file>
-- ============================================================

-- ── DB-level SELECT policy ────────────────────────────────────
DROP POLICY IF EXISTS "documents: read own rows" ON public.documents;
DROP POLICY IF EXISTS "documents: tiered read"  ON public.documents;

CREATE POLICY "documents: tiered read"
  ON public.documents FOR SELECT
  TO authenticated
  USING (
    visibility = 'common'
    OR (
      visibility = 'project'
      AND project_id IN (
        SELECT investor_units.project_id
        FROM public.investor_units
        WHERE investor_units.investor_id = (SELECT auth.uid())
      )
    )
    OR (
      visibility = 'investor'
      AND investor_id = (SELECT auth.uid())
    )
  );

COMMENT ON POLICY "documents: tiered read" ON public.documents IS
  'common=all authenticated; project=units-in-project; investor=own row.';

-- ── DB-level INSERT policy (investor-tier only) ───────────────
DROP POLICY IF EXISTS "documents: insert own investor doc" ON public.documents;

CREATE POLICY "documents: insert own investor doc"
  ON public.documents FOR INSERT
  TO authenticated
  WITH CHECK (
    visibility = 'investor'
    AND investor_id = (SELECT auth.uid())
  );

COMMENT ON POLICY "documents: insert own investor doc" ON public.documents IS
  'Investors can only attach their own personal documents. Common/project tiers go via service_role.';

-- ── Storage RLS ───────────────────────────────────────────────
-- Drop the legacy single-tier read policy and install three
-- per-tier policies. Service-role write policy from migration
-- 013_storage_buckets stays untouched (it grants full access
-- to service_role for the bucket).
DROP POLICY IF EXISTS "investors read own documents"
  ON storage.objects;
DROP POLICY IF EXISTS "investors read common documents"
  ON storage.objects;
DROP POLICY IF EXISTS "investors read project documents"
  ON storage.objects;
DROP POLICY IF EXISTS "investors read own investor documents"
  ON storage.objects;

-- common: every authenticated user
CREATE POLICY "investors read common documents"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'arl-documents'
    AND (storage.foldername(name))[1] = 'common'
  );

-- project: only investors who hold units in the path's project
CREATE POLICY "investors read project documents"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'arl-documents'
    AND (storage.foldername(name))[1] = 'project'
    AND (storage.foldername(name))[2] IN (
      SELECT project_id::text FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- investor: the owner only
CREATE POLICY "investors read own investor documents"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'arl-documents'
    AND (storage.foldername(name))[1] = 'investor'
    AND (storage.foldername(name))[2] = (SELECT auth.uid()::text)
  );

COMMENT ON POLICY "investors read common documents" ON storage.objects IS
  'arl-documents/common/* readable by all authenticated investors.';
COMMENT ON POLICY "investors read project documents" ON storage.objects IS
  'arl-documents/project/<project_id>/* readable when investor holds units in that project.';
COMMENT ON POLICY "investors read own investor documents" ON storage.objects IS
  'arl-documents/investor/<auth.uid()>/* readable by the owner only.';
