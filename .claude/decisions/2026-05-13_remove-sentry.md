# Remove half-wired Sentry integration

**Date:** 2026-05-13
**Status:** locked
**Phase:** Implement

## Context
`sentry_flutter` was added during early bring-up alongside a `SENTRY_DSN`
env entry, but no Sentry project was provisioned and the DSN was never
populated for any environment. The init path checked for a non-empty DSN
and would silently skip in every build we ever shipped, so the integration
provided zero signal while adding:

- A ~3 MB native dep (`sentry_flutter` 9.20 + transitive `sentry` 9.20).
- Cross-platform reflection surface that needs ProGuard `-keep` rules.
- An auth-state listener that called `Sentry.configureScope(...)` on every
  sign-in / sign-out, costing cycles + log noise for no observability.
- A maintenance burden every time Sentry's API drifts (major upgrades
  every 6–12 months).

## Decision
Remove `sentry_flutter` cleanly. Re-introduce only when there is a
provisioned Sentry project + a deployed channel + someone watching the
dashboards.

- `pubspec.yaml`: drop `sentry_flutter` dependency.
- `lib/main.dart`: drop `Sentry.init`, drop `SentryFlutter.init` wrapper
  around `appRunner`, drop the `Sentry.configureScope` calls inside the
  auth-state listener.
- `android/app/proguard-rules.pro`: drop the `-keep class io.sentry.**`
  block.
- No `SENTRY_DSN` referenced anywhere — `.env.example` already does not
  mention it after the env refactor.

## Why we're removing instead of fixing
- Without a Sentry project + alert routing, capturing errors goes
  nowhere. Production crashes are currently caught by Supabase server
  logs (for edge functions) and platform crash reporters (Play Console
  / TestFlight) once we eventually distribute through those channels.
- Distribution model is private (web URL, APK email, iOS bundle), so
  blast radius of an unobserved crash is small and crash reports come
  back as direct email from investors.

## Re-adding later
If telemetry becomes useful, the right shape is:

1. Provision Sentry project, decide which envs (dev / staging / prod)
   ship.
2. Set `SENTRY_DSN=...` in `.env.<env>`, read via
   `String.fromEnvironment('SENTRY_DSN')` (same pattern as Supabase).
3. Re-add `sentry_flutter` to `pubspec.yaml`.
4. Wrap `runApp` with `SentryFlutter.init` only when DSN is non-empty;
   sample at 10 %.
5. Restore the `Sentry.configureScope` user-id calls in the auth
   listener.
6. Restore the `-keep class io.sentry.**` ProGuard block.

The commit history holds the previous shape if a future agent wants to
reverse-apply it (search for `Sentry.configureScope` in git log).

## Verification
- `flutter pub get` — `sentry_flutter 9.20.0` + `sentry 9.20.0` shown
  as "no longer being depended on".
- `dart analyze lib` — no issues.
