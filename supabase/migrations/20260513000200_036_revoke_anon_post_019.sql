-- ============================================================
-- MIGRATION 036 — REVOKE anon CRUD on tables created after 019
--                 (S-004 remediation)
--
-- Audit finding S-004 (docs/security_audit_2026-05-13.md): migration
-- 019 (`019_revoke_default_grants.sql`) ran a blanket
-- `REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon`. That was a
-- snapshot — it only revoked from tables that existed at the time.
-- Tables created later inherit Postgres's default grants (which on
-- Supabase include `anon` via the schema-level GRANTs on
-- `public`), so RLS is the only line of defence — no defense in
-- depth.
--
-- Tables added between 020 and 029:
--   * sync_alerts             (mig 023)
--   * user_settings           (mig 026)
--   * login_events            (mig 026)
--   * consultation_requests   (mig 028)
--   * exit_requests           (mig 029)
--
-- Strategy: re-run the same blanket REVOKE migration 019 used. That
-- is idempotent for tables already covered AND closes the gap on the
-- 5 new tables in one statement. Then explicit per-table REVOKEs
-- below as documentation, so future readers grepping for a specific
-- table name find the protection and don't have to know that 019's
-- blanket was re-applied here.
--
-- The `GRANT SELECT ON public.app_config TO anon` line preserves the
-- single intentional anon read 019 carved out (used by the splash
-- screen for "Maintenance Mode" banner before login).
-- ============================================================

-- 1) Blanket re-run of the migration 019 posture, applied to every
--    table currently in `public`. Idempotent for the original set,
--    closes the post-019 gap for sync_alerts / user_settings /
--    login_events / consultation_requests / exit_requests.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT SELECT ON public.app_config TO anon;

-- 2) Explicit per-table REVOKEs for the post-019 set. Redundant
--    with the blanket above but makes intent obvious to anyone
--    grepping for the table name.
REVOKE ALL ON public.sync_alerts             FROM anon;
REVOKE ALL ON public.user_settings           FROM anon;
REVOKE ALL ON public.login_events            FROM anon;
REVOKE ALL ON public.consultation_requests   FROM anon;
REVOKE ALL ON public.exit_requests           FROM anon;

-- Verification (post-apply, run from psql/Studio):
--   SELECT table_name, privilege_type
--     FROM information_schema.role_table_grants
--    WHERE grantee = 'anon' AND table_schema = 'public'
--    ORDER BY table_name, privilege_type;
--   -- Expected: only one row — table_name='app_config', privilege_type='SELECT'.
--
-- Reversible: re-grant whatever a future feature legitimately needs
-- to anon by name; do NOT add anon back to ALL TABLES.
