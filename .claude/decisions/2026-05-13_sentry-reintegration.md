# Sentry reintegration — privacy-safe config

**Date:** 2026-05-13
**Status:** locked
**Reverses:** `6f417ad chore: remove half-wired sentry integration`

## Context

Sentry was previously stripped because the DSN was blank and shipping
a half-wired observer would only have produced noise. The user has now
created a real Sentry project (EU region, `growize-investor-portal`)
with custom server-side scrubbers configured for the sensitive fields
this app handles (PAN, Aadhaar, account number, IFSC, DOB, phone, PIN
hash). This branch wires the client into that project.

## Decision

1. **Region:** EU (`ingest.de.sentry.io`). Investor PII is governed by
   the Indian DPDP Act; storing crash artifacts in the EU keeps them
   under GDPR-grade controls and avoids US-jurisdiction exposure. The
   region is implicit in the DSN — no separate config knob.

2. **Privacy posture:**
   * `sendDefaultPii = false`. No IP, no auto-attached user identity.
     The auth-state listener in `main.dart` only attaches the supabase
     user id (a UUID), never email / phone.
   * `attachScreenshot = false`. KYC and bank screens render PAN /
     Aadhaar / account masks; a screenshot would defeat the masking.
   * `attachViewHierarchy = false`. Same reason — widget tree can
     carry text content of unmasked inputs.
   * `maxBreadcrumbs = 50`. Bounded.
   * `tracesSampleRate = 0.0`. Performance monitoring off for v1. Can
     flip later once we have a reason to want APM.
   * `diagnosticLevel = SentryLevel.warning`. Drop info noise.

3. **Defense in depth — client-side scrubber.**
   `lib/core/observability/sentry_config.dart` defines `scrubPii`
   which is wired as `options.beforeSend`. Patterns covered:
   PAN, Aadhaar (with separators), IFSC, +91 phone, email local-part,
   JWT-like, Bearer token, generic 9–18 digit run.
   Applied to: event message, exception values, breadcrumb messages
   and string-valued breadcrumb data. Server-side scrubbing is already
   on (custom sensitive fields are configured in the project), but we
   prefer to redact before transmit too — networks are not trusted.
   Choice: **redact in place rather than drop**. Losing a crash
   report is worse than shipping one with `<PAN_REDACTED>` in it.

4. **Compile-time DSN, never bundled into the binary.**
   `String.fromEnvironment('SENTRY_DSN')` (alongside
   `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE`). Empty DSN skips
   `SentryFlutter.init` entirely, so debug builds without the dart-
   define-from-file flag boot cleanly. Build line:
   ```
   flutter build web --release --dart-define-from-file=.env.production
   ```
   This diverges from how Supabase config is read today (dotenv asset),
   on purpose — secrets that we only want injected at release-build
   time should not also live as a runtime asset.

5. **Critical async paths instrumented.**
   `Sentry.captureException` added inside the catch blocks of:
   * Initial-setup KYC submit (`setup_screen.dart`)
   * Exit request submit (`exit_screen.dart`)
   * Consultation submit (`explore_screen.dart`)
   * Sign-in (password / OTP send / OTP verify in `login_screen.dart`)
   `on AuthException` blocks still swallow expected user-side errors;
   only the generic `catch (e)` branches report. Repository-level
   silent catches (projects, gallery, etc.) are intentionally NOT
   instrumented because they have graceful cache fallbacks and would
   produce a steady stream of offline-mode false positives.

6. **Dev-only Test Crash button.**
   In `profile_screen.dart`, hidden behind `kDebugMode ||
   SupabaseConstants.devBypassAuth`. Throws a stamped exception and
   surfaces a snackbar so the operator can verify integration end to
   end. Never compiles into a release build path that a real user
   would see, because `kDebugMode` is `const false` in `--release` and
   `devBypassAuth` is hard-coded to false in release mode (see
   `supabase_constants.dart:30`).

## What we did NOT do

* No `attachScreenshot`. Do not enable without a privacy review.
* No `sendDefaultPii`. Same.
* No performance monitoring spans / transactions. Out of scope.
* No `Sentry.captureMessage` calls anywhere — only exception capture.
* No structured logging integration. The existing repositories use
  `print` / `debugPrint`; that stays local.

## Files touched

* `pubspec.yaml` — already declares `sentry_flutter ^9.0.0`.
* `.env.example` — adds `SENTRY_DSN`, `SENTRY_ENVIRONMENT`,
  `SENTRY_RELEASE` placeholders with comments.
* `lib/core/observability/sentry_config.dart` — new. `scrubPii`,
  `scrubText`, `scrubNullable`.
* `lib/main.dart` — rewrites the Sentry init block.
* `lib/features/profile/profile_screen.dart` — dev-only Test Crash
  tile.
* `lib/features/auth/setup_screen.dart`,
  `lib/features/auth/login_screen.dart`,
  `lib/features/exit/exit_screen.dart`,
  `lib/features/explore/explore_screen.dart` — instrumented catches.
* `test/sentry_scrub_test.dart` — unit tests for the scrubber.
* `docs/ops_admin_guide.md` — Part 7 "Crash reporting (Sentry)".

## Operator runbook

* Set `SENTRY_DSN` in `.env.production` (gitignored) before any
  production / staging build. Set `SENTRY_ENVIRONMENT` per build env.
* To disable Sentry entirely for a given build, leave `SENTRY_DSN`
  empty in the .env file passed to `--dart-define-from-file`.
* After deploy, tap the dev-only Test Crash button on the Profile
  screen (in a dev build pointed at the production DSN) and verify
  the event lands in the Sentry dashboard with `<...REDACTED>`
  placeholders in any test PII you include in the message.
