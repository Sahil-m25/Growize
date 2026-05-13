# projects_public view — remediate S-002 coordinate leak

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Audit finding:** S-002 (High) — `docs/security_audit_2026-05-13.md`

## Problem
`ProjectsRepository` calls `client.from('projects').select()` with no
column list in four spots (marketplace, my-projects, project-by-id,
and a fallback). PostgREST translates that to `SELECT *`, so every
authenticated investor receives the full `projects` row — including
`latitude` / `longitude`. That contradicts the `LocationScreen`
privacy commitment that raw coords never leave the screen.

## Decision
Approach (a) from the prompt: create a SECURITY INVOKER view
`public.projects_public` that lists every safe-to-expose column
explicitly and OMITS `latitude` / `longitude`. Repoint the four
repository sites at the view. The model `project.dart` is updated
with a docstring block restating the rule.

Approach (b) (column-level REVOKE + RPC) was rejected: it changes
every reader's contract (would also break a future
LocationScreen that legitimately needs coords), and the view +
allowlist model is the same pattern migration 015 already
established for `portfolio_summary`.

### Migration (034)
- `ALTER TABLE public.projects ADD COLUMN IF NOT EXISTS … `
  idempotently backfills the marketplace / subscription columns
  that earlier `main`-branch / Studio edits added but that don't
  appear in this branch's migration sequence yet. No-op on the
  remote DB; required for the view definition to compile on a
  freshly-applied local DB.
- `CREATE VIEW public.projects_public WITH (security_invoker = on) AS SELECT … FROM public.projects`
  — every column except `latitude` / `longitude`.
- `GRANT SELECT ON public.projects_public TO authenticated`.
- Comment on view documents the privacy contract.

The view is **allowlist not denylist**: any new column added to
`public.projects` is invisible through the view until it is added
to the SELECT list. Intentional — every new column gets a
deliberate exposure decision.

### Client repointing
All four call sites in `lib/core/repositories/projects_repository.dart`
switched from `from('projects')` → `from('projects_public')`. No
other `.from('projects')` call sites exist in `lib/` (grep
confirmed).

`lib/features/projects/models/project.dart` gets a docstring block
restating: no `latitude`/`longitude` field on this model, reads go
through the view, future carve-outs must query `public.projects`
directly from the screen that needs it and comment with a pointer
to this audit finding.

### LocationScreen
Today's `LocationScreen` is a static placeholder ("Approximate
area"); it does not query coordinates. No code change there for
this fix. The view-only model future-proofs the privacy posture:
if/when a real map is wired up, the implementer will see the
docstring block and the audit pointer and make a deliberate choice
about whether to read `public.projects` directly.

## Touched files
- `supabase/migrations/20260513000000_034_projects_public_view.sql` (new)
- `lib/core/repositories/projects_repository.dart` (4 site repoint + docstring)
- `lib/features/projects/models/project.dart` (docstring block)
- `docs/security_audit_2026-05-13.md` (status flip — Fix 1)

## Verification
- `dart analyze lib` — clean.
- Post-apply SQL smoke (in ops doc Part 7):
  - `\d+ public.projects_public` shows no `latitude` / `longitude`
    columns.
  - `SELECT reloptions FROM pg_class WHERE relname='projects_public'`
    contains `security_invoker=on`.
  - `SELECT * FROM public.projects_public LIMIT 1` from a non-admin
    auth context returns RLS-scoped rows (existing migration 021
    policies apply through the view).

## Rollback
- `DROP VIEW IF EXISTS public.projects_public;`
- Revert the 4 lines in `projects_repository.dart` and the
  docstring block in `project.dart`.
- The `ALTER TABLE ADD COLUMN IF NOT EXISTS` block leaves columns
  in place — that's fine; they were already there on the live DB.
