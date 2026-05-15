-- ============================================================
-- MIGRATION 050 — drop the unused investors.address_line2 column.
--
-- Resolves: DEF-2026-05-15-17 (DEF-OPS-6).
--
-- The column was created in migration 002 as part of the
-- investors address block but no Zoho field maps to it and no
-- code path (Flutter, onboard-investor Edge Function, or
-- zoho-crm-webhook handleContact) reads or writes it. Confirmed
-- by grep across lib/, supabase/functions/, supabase/migrations/
-- before this migration — only definition site is migration 002.
-- ============================================================

ALTER TABLE public.investors
  DROP COLUMN IF EXISTS address_line2;

-- Rollback:
--   ALTER TABLE public.investors ADD COLUMN address_line2 TEXT;
--   -- Historical values are NOT recovered; if needed restore from snapshot.
