-- ============================================================
-- MIGRATION 047 — Drop the legacy 'documents/' prefix on
-- public.documents.storage_path; add CHECK to prevent drift.
--
-- Resolves: DEF-2026-05-15-02 (DOC-RLS-PATH).
--
-- Context:
--   Storage RLS for the arl-documents bucket reads
--   (storage.foldername(name))[1] and matches it against
--   'common' / 'project' / 'investor'. Migration 033's header
--   comment misleadingly described keys as
--   'documents/<tier>/<file>' but the policy itself authoritatively
--   uses '<tier>/<file>'. The four seed catalogue rows in
--   public.documents had paths with the legacy 'documents/'
--   prefix, so the catalogue and the storage policy would have
--   disagreed the moment ops uploaded any bytes.
--
-- Fix:
--   1) UPDATE the existing rows to strip the 'documents/' prefix.
--   2) Add a CHECK constraint preventing future rows from being
--      inserted with that prefix.
-- ============================================================

-- (1) Strip the legacy prefix from any existing rows.
UPDATE public.documents
   SET storage_path = substr(storage_path, length('documents/') + 1)
 WHERE storage_path LIKE 'documents/%';

-- (2) Reject future drift. Paths must start with one of the three
-- tier folders or be a legacy-shape relative path that doesn't
-- duplicate the bucket name.
ALTER TABLE public.documents
  ADD CONSTRAINT documents_storage_path_no_bucket_prefix
  CHECK (storage_path NOT LIKE 'documents/%');

COMMENT ON CONSTRAINT documents_storage_path_no_bucket_prefix
  ON public.documents IS
  'storage RLS reads folder level 1; paths must NOT include the '
  '''documents/'' bucket prefix. Use common/<file>, '
  'project/<uuid>/<file>, or investor/<uuid>/<file>.';

-- Rollback:
--   ALTER TABLE public.documents DROP CONSTRAINT documents_storage_path_no_bucket_prefix;
--   -- Path values are not reverted automatically; restore via snapshot.
