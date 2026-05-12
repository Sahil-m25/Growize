# ExitScreen — persist exit requests with duplicate guard

**Date:** 2026-05-12
**Phase:** Implement
**Status:** locked

## Problem
Audit row `ExitScreen (exit_screen.dart)` in `Flutter Feature Audit`
was Partial. The "Request Exit" CTA showed a snackbar only — no
persistence, no duplicate guard, no UI flip after submission.

## Decision
Persist exit requests to a new `public.exit_requests` table FK'd to
`public.investor_units(id)` — one allocation = one investment from the
investor's point of view. RLS scopes reads/writes to the user; ARL
staff resolve via service_role (Studio / future Edge Function).

### Schema (migration 029, applied)
- `exit_requests(id, investor_unit_id→investor_units, user_id→auth.users, reason text, status check(pending|approved|rejected|settled) default 'pending', created_at, resolved_at)`
- Index `(user_id, created_at DESC)`
- **Race-safe dedup:** `CREATE UNIQUE INDEX uniq_exit_requests_pending_unit ON exit_requests (investor_unit_id) WHERE status = 'pending'` — two concurrent submits can never both create pending rows for the same unit. Resolved rows don't count, so a rejected request can be re-filed.
- RLS on. Policies: `select own` + `insert own` (both `user_id = auth.uid()`)
- `GRANT SELECT, INSERT ON public.exit_requests TO authenticated`

### Repository / Provider
- `ExitRequestsRepository.createExit({investorUnitId, reason})` catches `PostgrestException` with code `23505` and re-fetches the existing pending row → returns `created: false, row: existing`. Cleaner than a `select-then-insert` race.
- `myPendingForUnit(investorUnitId)` returns the user's current pending row (if any).
- `_earliestInvestorUnitProvider` upgraded to return `{id, investment_date}` (was date-only) so the FK target is known to the screen.
- `_pendingExitForEarliestUnitProvider` drives the submitted-state card.

### UI flip
After a successful submit (or when a pending row already exists on entry), the CTA is replaced by a `_SubmittedCard` showing:
- "Exit request pending review"
- "Your request was submitted on `<date>`. ARL ops will reach out within 5 business days with valuation and settlement steps."

A reason dialog (3-line text, optional, max 500 chars) appears between
the CTA tap and the actual write — gives investors a place to leave
context without blocking submission.

## Touched files
- `supabase/migrations/20260512030000_029_exit_requests.sql` (new, applied)
- `lib/core/repositories/exit_requests_repository.dart` (new)
- `lib/core/providers/repositories.dart` (added `exitRequestsRepositoryProvider`)
- `lib/features/exit/exit_screen.dart` (ConsumerStatefulWidget, two new providers, reason dialog, submitted-state card)

## Verification
- Migration applied; verified columns + RLS enabled + 2 policies +
  partial unique index `uniq_exit_requests_pending_unit` with predicate
  `(status = 'pending'::text)`.
- `flutter pub get` — Got dependencies!
- `dart analyze lib` — `No issues found!`

## Rollback
- `DROP TABLE public.exit_requests;`
- Revert files listed above.
