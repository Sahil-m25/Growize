# REVOKE anon on post-019 tables — remediate S-004

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Audit finding:** S-004 (High) — `docs/security_audit_2026-05-13.md`

## Problem
Migration 019 (`019_revoke_default_grants.sql`) ran a blanket
`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon`. That was a
**snapshot** — Postgres applies the revoke to tables that existed
at the time. Tables created after 019 inherit the default schema
grants (which on Supabase include `anon` via implicit GRANTs on
`public`), so RLS is the only line of defence for them. No defense
in depth.

Tables created between 020 and 029 that this gap affects:
- `sync_alerts` (mig 023)
- `user_settings` (mig 026)
- `login_events` (mig 026)
- `consultation_requests` (mig 028)
- `exit_requests` (mig 029)

Mig 027 only modifies `public.investors` (already covered by 019).
The audit also referenced `kyc_resubmissions` (mig 030) but that
table does not yet exist in this branch — when it lands, the
authoring migration must mirror this REVOKE pattern. Note added to
the audit doc.

## Decision
Migration 036 re-runs migration 019's blanket
`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon` plus its
single carve-out `GRANT SELECT ON public.app_config TO anon`. The
blanket is idempotent for the originally-covered tables and closes
the gap on the 5 new ones in one statement.

Followed by **explicit per-table REVOKEs** for the post-019 set.
Redundant with the blanket, but searchable: someone grepping for
`user_settings` or `exit_requests` finds the protection without
having to know the blanket was re-applied here.

## Touched files
- `supabase/migrations/20260513000200_036_revoke_anon_post_019.sql` (new)

## Verification
Post-apply, from `psql` or Studio:

```sql
SELECT table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE grantee = 'anon' AND table_schema = 'public'
 ORDER BY table_name, privilege_type;
```

Expected: **one row** — `app_config` / `SELECT`.

Any other row is a regression and must be fixed in a follow-up
migration with a name that mirrors the table whose grant slipped
through.

## Rollback
Re-grant explicitly by table name as future features require:

```sql
GRANT SELECT ON public.<table> TO anon;
```

Do **not** re-grant `ALL TABLES IN SCHEMA public TO anon` — that
would reintroduce the same gap this migration closes.

## Process note
Any future migration that creates a new public table should end
with an explicit `REVOKE ALL ON public.<name> FROM anon` clause
(or skip it only if `anon` SELECT is genuinely required, in which
case GRANT just the specific privilege). The ops doc Part 7
captures this as a standing rule.
