-- ============================================================
-- MIGRATION 055 — Add zoho_file_id to project_documents
--
-- The `documents-sync` Edge Function mirrors Zoho
-- LLP_Creation_Module attachments into public.project_documents.
-- It needs a stable per-attachment key so the daily cron is
-- idempotent (re-running never duplicates a file). This mirrors
-- the existing `gallery_photos.zoho_file_id` pattern used by
-- gallery-sync, and the `documents.zoho_file_id` column already
-- present on the per-investor table.
--
-- Reversible:
--   DROP INDEX IF EXISTS public.project_documents_zoho_file_id_key;
--   ALTER TABLE public.project_documents DROP COLUMN IF EXISTS zoho_file_id;
-- ============================================================

ALTER TABLE public.project_documents
  ADD COLUMN IF NOT EXISTS zoho_file_id text;

COMMENT ON COLUMN public.project_documents.zoho_file_id IS
  'Zoho CRM attachment id. Set by documents-sync for files mirrored '
  'from LLP_Creation_Module; NULL for files uploaded manually via '
  'Supabase Studio. UNIQUE (where not null) so the daily sync is '
  'idempotent.';

-- Partial unique index: enforce uniqueness only for synced rows so
-- manually-uploaded rows (NULL zoho_file_id) are never blocked.
CREATE UNIQUE INDEX IF NOT EXISTS project_documents_zoho_file_id_key
  ON public.project_documents (zoho_file_id)
  WHERE zoho_file_id IS NOT NULL;
