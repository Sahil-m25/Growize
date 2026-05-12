-- ============================================================
-- MIGRATION 025 — Partial UNIQUE on investors.zoho_contact_id
--
-- Closes DEF-2026-05-11-05. Prevents two `investors` rows from
-- linking to the same Zoho CRM Contact. Partial: allows multiple
-- NULL values for manual/test investors with no CRM linkage, but
-- rejects duplicate non-NULL values.
--
-- Note: during application on 2026-05-11, a pre-existing constraint
-- `investors_zoho_contact_id_key` (full UNIQUE) was discovered already
-- enforcing the same rule. This partial UNIQUE coexists with it
-- harmlessly — Postgres treats NULL as distinct under both forms, so
-- behaviour is identical for the data we care about. Codifying the
-- intent here makes the schema self-documenting and gives a fresh
-- `db push` from this repo the same guarantee even if the historic
-- constraint is dropped or never reapplied.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS investors_zoho_contact_id_unique
  ON public.investors (zoho_contact_id)
  WHERE zoho_contact_id IS NOT NULL;

COMMENT ON INDEX public.investors_zoho_contact_id_unique IS
  'Partial UNIQUE on zoho_contact_id (NOT NULL only). Prevents '
  'duplicate-investor onboarding for the same Zoho Contact. '
  'Migration 025 / DEF-2026-05-11-05.';
