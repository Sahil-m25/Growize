# Env config refactor — dart-define-from-file

**Date:** 2026-05-13
**Status:** locked
**Phase:** Implement

## Context
Pre-refactor state read Supabase URL + anon key from a bundled `.env` file via
`flutter_dotenv`. The file was bundled as a Flutter asset (declared in
`pubspec.yaml`), which means real production credentials would ship inside the
release artefacts (apk, web build) and be visible via `assets/.env` over the
network.

This is acceptable for the anon key (it's a publishable key, gated by RLS) but
it conflated *deployment configuration* with *source-controlled constants*, and
made it impossible to build the same app for two environments without
swapping files at build time. `flutter_dotenv` also stops being useful on web
builds where the asset is downloaded over HTTP and parsed in JS.

## Decision
Replace `flutter_dotenv` with `--dart-define-from-file=<env file>` for all
environment-driven configuration. Configuration is now compiled into the
binary at build time via `String.fromEnvironment(...)`.

- `lib/core/constants/supabase_constants.dart` reads `SUPABASE_URL`,
  `SUPABASE_ANON_KEY`, `ARL_APP_MODE`, `ARL_DEV_BYPASS` via
  `String.fromEnvironment(...)` constants.
- `kReleaseMode` still asserts `isConfigured` and force-disables
  `devBypassAuth`.
- `lib/main.dart` no longer loads `dotenv` and no longer references Sentry.
- `pubspec.yaml`: `flutter_dotenv` + `sentry_flutter` dependencies removed;
  `.env` asset entry removed.
- `.env.example` rewritten to describe the dart-define-from-file workflow.
  Real values live in `.env.production` (gitignored).
- `.gitignore` now lists `.env.production`, `.env.staging` explicitly + iOS
  signing artefacts (`*.mobileprovision`, `*.p12`, `*.p8`, `ExportOptions.plist`).

## Why this approach
- **Works on web.** `String.fromEnvironment` is a `const` that Dart inlines at
  compile time, so the web bundle has the value baked into JS — no asset
  download, no runtime parse, no failure mode where the file is missing.
- **Multi-env builds.** `flutter build web --dart-define-from-file=.env.production`
  vs `--dart-define-from-file=.env.staging` produces two distinct artefacts
  from the same source tree.
- **No bundling of secrets.** Even though the anon key is publishable, this
  removes the temptation to put anything more sensitive into `.env`.
- **One fewer dep.** Drops `flutter_dotenv` (3rd-party, transitive deps).

## Build / run commands
```
flutter run --dart-define-from-file=.env.production
flutter build web   --release --dart-define-from-file=.env.production
flutter build apk   --release --dart-define-from-file=.env.production
flutter build ios   --release --dart-define-from-file=.env.production
```

`ARL_DEV_BYPASS=true` is honoured only in debug builds; release builds
force it to `false` regardless of the env file.

## Verification
- `flutter pub get` — dropped `flutter_dotenv` + `sentry_flutter`.
- `dart analyze lib` — no issues found.

## Out of scope / follow-ups
- Sentry is also removed (see separate decision `2026-05-13_remove-sentry.md`).
- Web build verification is in `2026-05-13_web-build-polish.md`.
