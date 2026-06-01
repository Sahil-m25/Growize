# Sentry smoke test

Use this to confirm crash reporting is live end-to-end. Takes ~1 minute.

1. **Build & launch a debug build** on a real device or emulator: `flutter run --dart-define-from-file=.env.production` (or your env file with `SENTRY_DSN` set). The DSN is read via `String.fromEnvironment('SENTRY_DSN')` in `lib/main.dart`; a debug build with an empty DSN will skip init silently.
2. **Open the app** → sign in → navigate to **Profile** (bottom tab).
3. **Tap "DEV — Send test crash to Sentry"** (red-bordered tile near the bottom of the Support section). This is gated on `kDebugMode` and is compiled out of `flutter build apk --release`. A snackbar should appear: "Test crash sent to Sentry (<timestamp>)".
4. **Open the Sentry EU dashboard** at https://sentry.io/ → project for Growize → Issues.
5. **Confirm the event arrives within 30s** with title containing `Sentry smoke test from Profile debug button at <timestamp>`. If it doesn't, check: (a) DSN is set in the env file, (b) device has network, (c) `sentry_dsn` value matches the project's DSN in Sentry settings.
