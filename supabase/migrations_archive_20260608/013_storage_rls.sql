-- ===================================================================
-- DEPRECATED — This file is superseded by:
--   20260414132751_013_storage_buckets.sql
--
-- The live database registered migration `013_storage_buckets` (with a
-- 14-digit timestamp version), not this hand-crafted file. Worse, the
-- path convention this file used (`foldername(name)[1] = auth.uid()`)
-- did not match the actual storage layout (`documents/{investor_id}/...`),
-- so applying this file by mistake would have broken document reads.
--
-- All migrations were materialised from supabase_migrations.schema_migrations
-- on 2026-04-27 with proper <14-digit-version>_<name>.sql filenames so
-- `supabase db push` recognises them as already-applied.
--
-- This file is kept in the repo for git history only — it does NOT run
-- (the only statement is this comment block). Safe to delete entirely
-- once the team has confirmed the materialised migrations.
-- ===================================================================

SELECT 1 WHERE FALSE;  -- intentional no-op; preserves the file as valid SQL.
