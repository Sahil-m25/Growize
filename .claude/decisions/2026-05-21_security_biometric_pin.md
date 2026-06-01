# Real biometric + PIN app-lock gate

**Date:** 2026-05-21
**Status:** locked
**Phase:** Implement
**Files touched:**
- `lib/core/auth/app_lock_service.dart` (new)
- `lib/core/auth/app_lock_provider.dart` (new)
- `lib/features/auth/lock_screen.dart` (new)
- `lib/main.dart` (lifecycle observer + lock overlay)
- `lib/features/profile/security_screen.dart` (re-wired toggles)
- `lib/features/auth/auth_provider.dart` (clear lock state on sign-out)
- `lib/core/auth/biometric_guard.dart` (web no-op + try/catch)

## Why

User feedback: "Security features are gimmicks. They look like they work but nothing actually challenges the user."

## Audit (what was theater)

| Surface | Pre-change reality |
|---|---|
| `SecurityScreen` Biometric Login toggle | Persisted a flag in `user_settings.biometric_enabled` and gated `LoginScreen`'s "use biometric" shortcut, but never gated app entry. |
| `SecurityScreen` App PIN | Set/changed/removed a salted SHA-256 hash in `user_settings.app_pin_hash`. Nothing ever prompted for the PIN at runtime. Only the "change PIN" flow asked for it (to authorise the change). |
| `BiometricScreen` (`/biometric`) | Used as an enrollment-confirmation gate (pushed from SecurityScreen, pops `true/false`). Not a runtime gate. |
| "Auto-lock after 5 minutes" row | Static label. No state, no behaviour, no setting. |
| Resume-after-background | Nothing. `ArlApp` was a `ConsumerWidget` with no lifecycle observer. |
| Web | `BiometricGuard` called `local_auth` unconditionally — its web support is unreliable. |

## What was built

### `AppLockService` (per-device, secure-storage-backed)
- Stores `pin_hash`, `pin_salt`, `pin_iterations`, `biometric_enabled`, `pin_required` under `arl.lock.*` keys in `flutter_secure_storage` (EncryptedSharedPreferences on Android, Keychain on iOS, IndexedDB on web).
- `setPin(pin)` -> random 16-byte salt + 100k-iter SHA-256(salt || pin), base64.
- `verifyPin(pin)` -> constant-time compare.
- `biometricAvailable()` returns `false` on web; otherwise wraps `LocalAuthentication.canCheckBiometrics || isDeviceSupported`.
- `biometricEnrolled()` exposes "any biometric registered with the OS?" so the lock screen can show a "enroll a fingerprint" hint when the toggle is on but the device has nothing matched.
- `authenticateBiometric()` calls `LocalAuthentication.authenticate` with `biometricOnly: false` (allows device passcode as fallback) and `stickyAuth: true`.
- `resumeGrace` constant = 30s.

**Why a local PIN store separate from `user_settings.app_pin_hash`:** the runtime gate must work fully offline, including cold launch before any network call. The server hash is still mirrored by SecurityScreen so the legacy "change PIN" path on other devices keeps working, but the lock-screen's source of truth is local.

### `appLockProvider`
- `appLockSettingsProvider` (FutureProvider<AppLockSettings>) — reads service.
- `appLockedProvider` (StateProvider<bool>) — runtime "is the app locked?" flag. Defaults `true` so cold launch decides based on actual settings without flashing protected content first.
- `lastBackgroundedAtProvider` (StateProvider<DateTime?>) — timestamp for the grace-window logic.
- `appLockControllerProvider` exposes a controller object screens use to mutate state without each consumer hand-invalidating the FutureProvider.
- `lockBootProvider` — convenience that resolves settings and, as a side effect, flips `appLockedProvider` to false when nothing is configured.

### `LockScreen`
Full-screen ConsumerStatefulWidget overlaid by `_LockGate` in `main.dart`:
1. If biometric is enabled and the OS has at least one enrolled, the biometric sheet is prompted on first build (`addPostFrameCallback`).
2. If biometric isn't enrolled but the user has a PIN, the lock screen surfaces a "no fingerprint enrolled… use your PIN" hint and skips straight to the PIN field.
3. PIN entry: obscured 4-6 digit field. 3 wrong attempts -> 30-second cooldown (live-updating). No sign-out; private launch.
4. Visual: `ArlColors.primary` background, gold accents, Inter font, no emoji.

### `ArlApp` lifecycle gate
- Was `ConsumerWidget`. Now `ConsumerStatefulWidget` with `WidgetsBindingObserver`.
- `inactive`/`paused`/`hidden` -> `controller.noteBackgrounded()` (stamps the time; doesn't lock immediately because the user might be looking at a notification shade).
- `resumed` -> if a lock is configured AND >=30s have passed since the last backgrounding stamp, flip `appLockedProvider` to true.
- A `_LockGate` widget wraps the router child:
  - Signed-out -> pass through (sign-in screens own their own flow).
  - Locked + settings still loading -> neutral splash (no content leak).
  - Locked + lock configured -> `LockScreen` over an `Offstage` of the router child (preserves widget-tree state).
  - Otherwise pass through.

### `SecurityScreen` rewrite
Three real toggles, all backed by `AppLockController`:
- Biometric unlock — toggling on requires a successful biometric check first (proves identity before the gate goes live). Helpful errors when the device is unsupported or has no enrolled fingerprint.
- Require PIN — disabled until a PIN is set. Distinct tile from the PIN management tile.
- App PIN (Set/Change/Remove) — writes both the local hash (used by lock screen) AND the server hash (kept for legacy cross-device change-PIN flow). Setting the PIN auto-enables the "Require PIN" toggle.
- Inline "you'll be asked to verify…" hint card explaining what's active.

### Sign-out cleanup
`auth_provider.dart` now clears `AppLockService` storage AND invalidates `appLockSettingsProvider` on `signedOut`. Keeps device-shared scenarios honest — a different user signing in shouldn't inherit the previous user's PIN.

### Web
`AppLockService.biometricAvailable()` short-circuits to false on `kIsWeb`. PIN-only still works via `flutter_secure_storage`'s web backend.

## Decisions

1. Local PIN as source of truth for the gate, server PIN as mirror. Alternative: server-only. Rejected — cold launch with no network would break the gate. Drawback: the two can drift if PIN is changed on another device — accepted, since the gate is a per-device decision anyway.
2. `biometricOnly: false` — allows OS device-credential fallback. A user with a damp finger shouldn't be forced through PIN entry when the OS can already authenticate them.
3. 30-second resume grace. Short enough that an unattended phone re-locks quickly; long enough that brief OS switches (notification, camera, share sheet) don't nag.
4. Failed PIN doesn't sign out. 3 wrong attempts -> 30s cooldown only. Private launch — no need to push the user through full re-auth.
5. Wipe lock state on sign-out, not on sign-in. Sign-out implies "different user might pick up this device". Sign-in is intentionally a clean slate.

## Test plan (manual)

On Android/iOS device:
1. Cold launch, sign in. Confirm no lock screen (nothing configured).
2. Profile -> Security -> toggle Biometric unlock. Biometric prompt fires; on success the toggle stays on.
3. Background the app for >=30 s. Re-open. Lock screen shows; tapping fingerprint unlocks.
4. Background again, tap PIN field instead of biometric (or cancel biometric).
5. Profile -> Security -> Set App PIN. Confirm "Require PIN" auto-enables.
6. Background >=30 s. Wrong PIN three times -> 30s cooldown banner. Wait it out -> reset.
7. Enter correct PIN -> unlocks.
8. Sign out, sign back in. Confirm no lock screen until re-enrolled.
9. Kill the app, cold-launch with biometric+PIN both enabled. Lock screen appears before any app content.

On web (Chrome):
1. Biometric toggle should show "not available on this device" error.
2. PIN flow should work end-to-end via IndexedDB.
3. PIN-only lock should gate cold launch after a tab-visibility change.

## Follow-ups (not in scope)

- Configurable grace window (currently fixed at 30 s).
- Optional sign-out-after-N-fails (currently off for private launch).
- "Lock now" button on the profile screen for demoing the flow.
