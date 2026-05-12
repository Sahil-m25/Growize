# ExploreScreen — persist consultation requests

**Date:** 2026-05-12
**Phase:** Implement
**Status:** locked

## Problem
Audit row `ExploreScreen (explore_screen.dart)` in `Flutter Feature
Audit` was Partial. The "Request Consultation" CTA showed a confirm
snackbar with a TODO comment — nothing was persisted, no dedup, no
in-flight state.

## Decision
Persist consultation requests to a new `public.consultation_requests`
table, RLS-scoped to the writing user. ARL ops works the queue via
service_role (Supabase Studio) — same staff-access pattern as
`support_tickets` and `bank_change_requests`. No new admin DB role.

### Schema (migration 028)
- `consultation_requests(id, user_id→auth.users, project_id→projects, units_requested int, message text, status check(new|contacted|closed) default 'new', created_at)`
- Indexes: `(user_id, created_at DESC)`, `(project_id, status, created_at DESC)`
- RLS on. Policies: `select own` + `insert own` (both `user_id = auth.uid()`)
- `GRANT SELECT, INSERT ON public.consultation_requests TO authenticated`

### Dedup
Client-side 24h check against the user's own `new` rows. Chose a
client query over a DB partial unique index because: requests are
expected to be naturally low-volume per user, and we want the user
to be able to file a *fresh* consultation 24h later without an admin
flipping status. A unique index would force staff intervention.

### UI
- Per-project `_submittingProjectIds` set on `_ExploreScreenState`
- Button disabled when project id is in the set; child swapped for an
  inline `CircularProgressIndicator`
- On success: toast distinguishes "Got it — we'll reach out" vs.
  "already requested recently"
- On error: toast with error message; button re-enables in `finally`

## Touched files
- `supabase/migrations/20260512020000_028_consultation_requests.sql` (new, applied)
- `lib/core/repositories/consultation_requests_repository.dart` (new)
- `lib/core/providers/repositories.dart` (added `consultationRequestsRepositoryProvider`)
- `lib/features/explore/explore_screen.dart` (wired CTA, in-flight set, dedup-aware toast)

## Verification
- Migration applied via `supabase db query --linked -f ...028*.sql`. RLS
  enabled, both policies present, grants confirmed.
- `flutter pub get` — Got dependencies!
- `dart analyze lib` — `No issues found!`

## Rollback
- `DROP TABLE public.consultation_requests;`
- Revert files listed above.
