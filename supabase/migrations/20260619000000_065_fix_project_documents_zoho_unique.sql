-- Migration 065: Fix project_documents.zoho_file_id unique index
--
-- The partial unique index (WHERE zoho_file_id IS NOT NULL) prevented
-- Supabase JS upsert's ON CONFLICT (zoho_file_id) from resolving the
-- conflict target, causing documents-sync to silently fail inserting
-- project document rows while still incrementing its counter.
--
-- Replace with a full unique constraint. NULL values still don't conflict
-- with each other (SQL NULL != NULL semantics), so multiple unlinked rows
-- with zoho_file_id = NULL remain valid.

DROP INDEX IF EXISTS project_documents_zoho_file_id_key;
ALTER TABLE project_documents
  ADD CONSTRAINT project_documents_zoho_file_id_key UNIQUE (zoho_file_id);
