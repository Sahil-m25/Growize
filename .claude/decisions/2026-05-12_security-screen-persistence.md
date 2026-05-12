# SecurityScreen persistence + login audit trail

**Date:** 2026-05-12
**Phase:** Implement
**Status:** locked

## Problem
Audit row `SecurityScreen (security_screen.dart)` in `ARL_Test_Tracker.xlsx`
sheet `Flutter Feature Audit` was Fail:
- biometric/notifications toggles were local `setState` only — nothing
  persisted across sessions or devices,
- App PIN row was a snackbar stub (`coming soon`),
- "Last login" + "Login history" text was hardcoded.

## Decision
Persist preferences and PIN to a new `user_settings` table (one row per
auth user) and record every successful sign-in into a new append-only
`login_events` table. RLS scopes both tables to `auth.uid()`. The app
PIN is hashed client-side (salt + 100k iterations of SHA-256) before
the row is ever sent — the database never receives a plaintext PIN.

### Schema (migration 026)
- `public.user_settings`
  - `user_id UUID PK FK auth.users(id)`
  - `biometric_enabled BOOLEAN DEFAULT FALSE`
  - `notifications_enabled BOOLEAN DEFAULT TRUE`
  - `app_pin_hash TEXT` (NULL = unset), `app_pin_salt TEXT`, `app_pin_iterations INT`
  - `updated_at TIMESTAMPTZ` (trigger via existing `public.set_updated_at`)
  - RLS: SELECT/INSERT/UPDATE where `user_id = auth.uid()`
- `public.login_events`
  - `id UUID PK`, `user_id UUID FK`, `occurred_at TIMESTAMPTZ`
  - `device_label`, `platform`, `app_version`, `user_agent`
  - index `(user_id, occurred_at DESC)`
  - RLS: SELECT/INSERT where `user_id = auth.uid()` — no UPDATE/DELETE
    policy = append-only from the client
- Service role bypasses RLS (Edge Functions can write/maintain rows).

### Why client-side PIN hashing
The Supabase `authenticated` JWT can write the row, so we cannot rely
on DB-side hashing without an Edge Function. Doing it on the client
with a 16-byte random salt + 100k SHA-256 iterations keeps the cost
proportionate (4-6 digit PINs are low-entropy anyway — the salt is
what blocks rainbow tables and per-user reuse). PIN verification
recomputes the hash with the stored salt + iteration count and
constant-time-compares.

### Why `user_id` FK → `auth.users` (not `investors`)
Migration 009 already keys `investors.id = auth.uid()`, but a brand-new
sign-up has an auth user before the investor row is created during
onboarding. Settings should be reachable in that window too.

## Touched files
- `supabase/migrations/20260512000000_026_user_settings_and_login_events.sql` (new)
- `lib/core/repositories/user_settings_repository.dart` (new)
- `lib/core/repositories/login_events_repository.dart` (new)
- `lib/core/providers/repositories.dart` (added providers + `userSettingsProvider`, `myLoginEventsProvider`)
- `lib/features/auth/auth_provider.dart` (records login on `AuthChangeEvent.signedIn`)
- `lib/features/profile/security_screen.dart` (full rewrite as ConsumerWidget)
- `pubspec.yaml` (`crypto: ^3.0.3` declared explicitly)

## Verification
- `flutter pub get` — Changed 1 dependency.
- `dart analyze lib` — `No issues found!`
- Migration application: deferred — Supabase MCP requires OAuth (user
  must complete the authorize flow; CLI `db push` is blocked by
  diverged migration history with the remote project — repairing
  that is out of scope for this priority).

## Rollback
- `DROP TABLE public.login_events;`
- `DROP TABLE public.user_settings;`
- Revert files listed above.
