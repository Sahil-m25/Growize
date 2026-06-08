-- ============================================================
-- MIGRATION 057 — Allow 'documents_sync' as a webhook_log source
--
-- The documents-sync Edge Function logs each run to webhook_log
-- (source='documents_sync'), mirroring gallery-sync. The original
-- webhook_log_source_check CHECK only allowed
-- ('zoho_crm','zoho_books','gallery_sync','manual'), so those log
-- rows were silently rejected — leaving sync runs invisible to ops
-- dashboards and the sync-stale-alert monitor. Add the new source.
--
-- Reversible:
--   ALTER TABLE public.webhook_log DROP CONSTRAINT webhook_log_source_check;
--   ALTER TABLE public.webhook_log ADD CONSTRAINT webhook_log_source_check
--     CHECK (source = ANY (ARRAY['zoho_crm','zoho_books','gallery_sync','manual']));
-- ============================================================

ALTER TABLE public.webhook_log DROP CONSTRAINT webhook_log_source_check;

ALTER TABLE public.webhook_log ADD CONSTRAINT webhook_log_source_check
  CHECK (source = ANY (ARRAY['zoho_crm'::text, 'zoho_books'::text, 'gallery_sync'::text, 'documents_sync'::text, 'manual'::text]));
