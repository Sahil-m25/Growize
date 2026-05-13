# Android release signing scaffold

**Date:** 2026-05-13
**Status:** locked
**Phase:** Implement (ship readiness)

## Context
Private distribution model: signed release APKs are emailed directly to
investors — no Play Console enrolment, no internal-track upload, no
managed signing. We need the build to *be able to* produce a signed
release artefact without committing the keystore or its password to git.
The previous state of the repo already had `signingConfigs.release` wired
in `android/app/build.gradle.kts`, but no `key.properties.example` to
guide first-time keystore generation.

## Decision

### `android/app/build.gradle.kts` (unchanged — verified in place)
- Reads `android/key.properties` if the file exists.
- Defines `signingConfigs.release` only when `hasReleaseKeystore` is
  true.
- `buildTypes.release.signingConfig` falls back to debug signing when
  `key.properties` is absent, so `flutter run --release` keeps working
  for development without a keystore.

### `android/key.properties` — gitignored
- Already listed in `.gitignore` (along with `android/app/*.jks`).
- Never committed.

### `android/key.properties.example` — checked in (new)
- Documents the four required keys (`storePassword`, `keyPassword`,
  `keyAlias`, `storeFile`) with placeholder values.
- Inlines the exact `keytool` command to generate the keystore and the
  reminder that losing the `.jks` permanently blocks signed updates
  for this `applicationId` — back it up to a password manager vault.

## Keystore generation (manual, one-off)

```
keytool -genkey -v \
  -keystore arl-release-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias arl-release
```

Interactive — sets `keyAlias` + `storePassword` + `keyPassword`. Place
the resulting `arl-release-key.jks` in `android/app/`. Copy
`android/key.properties.example` to `android/key.properties` and fill
in the matching passwords + alias.

Build:
```
flutter build apk --release --dart-define-from-file=.env.production
flutter build appbundle --release --dart-define-from-file=.env.production
```

Output:
- APK → `build/app/outputs/flutter-apk/app-release.apk`
- AAB → `build/app/outputs/bundle/release/app-release.aab` (kept around
  in case Play Console enrolment happens later — not used for direct
  email distribution).

## Why no auto-generated keystore
- `keytool` requires interactive password prompts. Generating one in CI
  without an attended prompt means hard-coding passwords, which defeats
  the purpose.
- Loss of the keystore is non-recoverable: a new keystore means a new
  `applicationId` and reinstall-from-scratch for every existing
  investor.

## Verification
- `android/app/build.gradle.kts` — confirmed `hasReleaseKeystore` guard
  + fallback to debug.
- `.gitignore` — `android/key.properties` + `android/app/*.jks` listed.
- `android/key.properties.example` — new file with documented `keytool`
  command.
- Real keystore generation deferred to user (left as a launch-readiness
  action item in `ARL_Test_Tracker.xlsx`).
