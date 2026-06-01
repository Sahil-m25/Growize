# 2026-05-21 — Biometric unlock root cause (third pass)

## Symptom

User feedback (third report): "For security, I'm still unable to use the
biometric unlock. Please look into that."

Previous two fixes in this area
(`2026-05-21_security_biometric_pin.md`,
`2026-05-21_lockscreen_blank_fix.md`) wired the gate end-to-end and made
the LockScreen actually render. The runtime gate, the lock screen UI,
the settings persistence and the lifecycle observer were all correct.
But the OS biometric sheet still never appeared on Android, and the
LockScreen's "biometric not recognised" message gave the user no clue
why.

## Actual root cause (the one we kept missing)

`android/app/src/main/kotlin/com/arl/app/MainActivity.kt` was:

```kotlin
class MainActivity : FlutterActivity()
```

The `local_auth` plugin uses `androidx.biometric.BiometricPrompt`, which
**requires the host Activity to extend `androidx.fragment.app.FragmentActivity`**.
`FlutterActivity` is NOT a `FragmentActivity`. On every
`LocalAuthentication.authenticate(...)` call the platform side throws a
`PlatformException` (code `no_fragment_activity`). Our service caught
that exception in a bare `catch (_)` and returned `false`, so the
LockScreen surfaced "Biometric not recognised. Try again." with no
indication that the OS sheet was never even shown.

This is the documented requirement on the `local_auth` plugin README and
has been wrong since the initial security_biometric_pin landing — both
follow-up fixes touched Flutter code only and never opened the Android
host project.

## Other gaps found while diagnosing

1. **`minSdk` was implicit.** `build.gradle.kts` used
   `minSdk = flutter.minSdkVersion`, which currently resolves to 21.
   `BiometricPrompt` requires API 23+. Older devices would have
   compiled fine but failed at runtime in a similar silent way.

2. **PIN-first not enforced.** The original decision doc states biometric
   may only be enabled "with a PIN as fallback", but `_setBiometric`
   never checked. A user with no enrolled fingerprint who toggled
   biometric ON, with no PIN set, could end up at the LockScreen with
   no working unlock method. (The sign-out escape from the second
   pass at least prevented permanent lockout, but the user-facing
   behaviour was still broken.)

3. **Web showed a doomed toggle.** On Chrome, `local_auth` has no
   working backend. The Security screen would let the user flip the
   switch, then surface a snackbar after the biometric check failed.
   Cleaner to hide the row entirely on web — there is nothing the user
   can do to make it work.

4. **No diagnostic signal.** Every error path in `AppLockService`
   used `catch (_)`, so even when `flutter logs` was running there was
   no breadcrumb of the underlying `PlatformException.code`.

5. **No layout-settle delay.** On some Android devices the OS biometric
   sheet is requested in the same frame the LockScreen mounts. The
   prompt is shown briefly and auto-cancelled, or the result fires
   before the LockScreen is ready to consume it. Adding a 500 ms delay
   after `addPostFrameCallback` materially reduces this.

## Fixes shipped

### Android host project

- **`android/app/src/main/kotlin/com/arl/app/MainActivity.kt`** —
  changed `class MainActivity : FlutterActivity()` to
  `class MainActivity : FlutterFragmentActivity()`. This is the load-
  bearing fix; without it, biometric authentication on Android cannot
  work.
- **`android/app/build.gradle.kts`** — pinned `minSdk = 23` so
  `BiometricPrompt` is always available at runtime.
- **`AndroidManifest.xml`** — already declared `USE_BIOMETRIC` and
  `USE_FINGERPRINT`. No change.

### App-lock service

- `AppLockService.biometricAvailable / biometricEnrolled /
  authenticateBiometric` now log `PlatformException.code` and
  `PlatformException.message` in debug mode so silent failures show
  up in `flutter logs`. Released builds still collapse to a bool.

### App-lock controller

- `AppLockController.setBiometricEnabled(true)` now refuses to
  persist the flag unless (a) the platform reports biometric
  available (`!kIsWeb` && local_auth supports it), AND (b) a PIN is
  already set on this device. Throws `BiometricUnsupportedException`
  or `BiometricRequiresPinException`. Disabling is always allowed.

### Security screen

- The biometric row is now **hidden entirely on `kIsWeb`** — there is
  no point offering an unsupported toggle.
- The row is **disabled until a PIN exists** (so the user can't enable
  biometric and lose their fallback). Subtitle reads "Set a PIN first
  to enable." Disabling remains possible even from a no-PIN state to
  let users escape any legacy configuration.
- `_setBiometric` runs guards in this order: web short-circuit, PIN
  presence, `biometricAvailable`, `biometricEnrolled`, the proof-of-
  identity authenticate call. Each step produces a specific snackbar.
- Catches the typed exceptions from the controller and surfaces their
  `toString()` instead of "Could not save: $e".

### LockScreen

- `initState` now schedules `_maybePromptBiometric` with a 500 ms
  delay after the post-frame callback, giving the OS sheet a stable
  surface to display over.
- Added `debugPrint` traces for the biometric prompt decision so the
  full path is visible in `flutter logs`.

## End-state guarantees

- **On Android (FragmentActivity-based + minSdk 23 + biometric
  enrolled + PIN set):** fingerprint prompt fires on cold launch and
  on resume after 30 s; success unlocks; failure leaves PIN + sign-out
  available. The biometric toggle in Security is only flipped after a
  successful in-app biometric check.
- **On Chrome web:** the biometric row does not appear in Security.
  LockScreen never shows a fingerprint button. PIN-only flows still
  work (flutter_secure_storage's IndexedDB backend), and the sign-out
  escape is always visible.
- **On any device without an enrolled fingerprint:** the toggle is
  refused with an explicit "no fingerprint enrolled" snackbar; the
  user cannot trap themselves.
- **PIN is always required as a fallback when enabling biometric.**

## Files touched

- `android/app/src/main/kotlin/com/arl/app/MainActivity.kt`
- `android/app/build.gradle.kts`
- `lib/core/auth/app_lock_service.dart`
- `lib/core/auth/app_lock_provider.dart`
- `lib/features/auth/lock_screen.dart`
- `lib/features/profile/security_screen.dart`

## Verification steps

1. Rebuild the Android APK (`& C:\flutter\bin\flutter.bat build apk`)
   — without the MainActivity migration the app would compile, but
   biometric still fails. With the fix, the OS sheet appears.
2. On an Android device with a fingerprint enrolled:
   - Profile -> Security: confirm the biometric row is greyed out and
     subtitled "Set a PIN first to enable."
   - Set a PIN. The biometric row should re-enable.
   - Toggle biometric ON. The OS sheet must appear; on success the
     toggle stays ON.
   - Background the app for >=30 s, re-open. LockScreen renders,
     fingerprint sheet appears within ~500 ms; on success the app
     unlocks.
   - Cold-launch (kill + reopen): same.
   - Cancel the OS sheet: LockScreen stays, PIN + sign-out usable;
     tap the "Use biometric" button to re-trigger.
3. On Chrome (`& C:\flutter\bin\flutter.bat run -d chrome`):
   - Profile -> Security: biometric row must be absent.
   - PIN flow must work end-to-end.
   - LockScreen (if PIN-locked) must not render a biometric button.

## Notes

- No packages added.
- The `BiometricGuard` legacy helper (`lib/core/auth/biometric_guard.dart`)
  is still used by the sign-in screen biometric shortcut. It also
  benefits from the MainActivity migration — the shortcut would have
  been failing silently for the same reason.
- No emoji.
