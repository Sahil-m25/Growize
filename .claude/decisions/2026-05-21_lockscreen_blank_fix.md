# 2026-05-21 — LockScreen blank-screen fix

## Symptom

After enabling biometric in Profile -> Security, on next cold-launch
(or on resume after the 30s grace window), the user saw a blank
dark-green screen instead of the `LockScreen` widget. The lock gate
was firing (`appLockedProvider == true`) and the build tree was
reaching the `LockScreen` widget, but nothing painted.

## Root cause

In `lib/main.dart`, `_LockGate` rendered the lock UI like this:

```dart
return Stack(
  children: [
    Offstage(offstage: true, child: child), // router content, hidden
    const Positioned.fill(
      child: Material(
        color: ArlColors.primary,
        child: LockScreen(),
      ),
    ),
  ],
);
```

`Stack` defaults to sizing itself to fit its non-positioned children.
The only non-positioned child here was `Offstage(offstage: true, ...)`
- and an offstage widget has zero layout size.

So the Stack collapsed to 0x0. `Positioned.fill` then "filled" that
zero-sized box, and `LockScreen` got laid out with
`BoxConstraints.tight(Size.zero)`. Result: a Scaffold building into
nothing - blank screen.

The lock screen was correctly wired everywhere else; it just had no
canvas.

## Secondary issues found while diagnosing

1. Web could dangle an unusable biometric button. `LockScreen.build`
   computed `canUseBiometric = settings.biometricEnabled` without
   consulting `local_auth.isDeviceSupported()`. On web,
   `AppLockService.biometricAvailable()` returns `false`, so the
   button tap was a no-op.

2. No ultimate bypass. If biometric was the only configured method
   and the device's biometric became unavailable (sensor disabled,
   enrolled fingerprint removed, web), the screen offered no way out.

3. `_attemptedBiometric` was burned even on platform-unsupported path,
   so a retry tap did nothing on devices where biometric wasn't
   actually callable.

4. `appLockSettingsProvider` loading state rendered a `ColoredBox`
   without an outer size guarantee. In the same `Offstage`-trapped
   Stack, even the loading splash would be invisible.

## Fixes

### `lib/main.dart`

- Changed `Stack(...)` to `Stack(fit: StackFit.expand, ...)` so the
  stack expands to its parent constraints instead of shrinking to fit
  the zero-sized offstage child.
- Replaced the redundant `Material` wrapper around `LockScreen` with a
  `ColoredBox(ArlColors.primary)` backstop.
- Wrapped the `settings == null` loading splash in `SizedBox.expand`
  so it claims the full pane even under loose constraints.

### `lib/features/auth/lock_screen.dart`

- Added `_biometricSupported` + `_platformChecked` state, populated by
  an async `_refreshPlatformSupport()` on first frame via
  `AppLockController.biometricAvailable()`. The biometric button now
  only renders when the user opted in AND the platform reports
  support - on web it stays hidden.
- Reworked `_maybePromptBiometric()` to NOT consume the one-shot
  `_attemptedBiometric` latch when the platform reports unsupported.
- Added `_signOutEscape()` and an always-visible "Sign out and log
  back in" `TextButton` at the bottom of the LockScreen, regardless
  of which auth methods are configured. Ultimate bypass.
- Restructured the body as `SafeArea -> SizedBox.expand ->
  SingleChildScrollView -> ConstrainedBox(minHeight: viewport) ->
  IntrinsicHeight -> Column(mainAxisSize: max, ..., Spacer(),
  sign-out)`, the documented Flutter sticky-footer-in-scroll idiom.
- Added an explicit "Growize" wordmark above the "App is locked"
  header so the screen always identifies itself.
- Added a defensive "no auth method available" panel that explains
  the situation and directs the user at the sign-out escape.

## End-state guarantees

After this change, the lock screen always renders at least:

- The Growize wordmark
- The "App is locked" header
- A descriptive subtitle
- At least one of: biometric button, PIN entry, or the "no auth
  available" explainer panel
- The "Sign out and log back in" escape at the bottom

There is no code path that produces a blank screen while
`appLockedProvider` is true.

## Files changed

- `lib/main.dart`
- `lib/features/auth/lock_screen.dart`

## Verification steps for the user

1. Run `& C:\flutter\bin\dart.bat analyze lib` - should pass clean.
2. `& C:\flutter\bin\flutter.bat run -d chrome` or on an Android
   device.
3. Sign in.
4. Profile -> Security -> enable biometric (set a PIN too).
5. Background the app, wait 30+ seconds, return - LockScreen must
   render with fingerprint button + PIN field + sign-out link.
6. Cold-launch (kill + reopen) - same.
7. On a device with biometric enrolled, tap the fingerprint button.
8. Cancel the OS sheet - LockScreen stays, PIN/sign-out usable.
9. Web build: biometric button must not appear; PIN field appears if
   a PIN exists; sign-out link always appears.
10. Biometric enabled but no enrolled fingerprint: error panel
    explains, PIN fallback usable, sign-out visible.

## Notes

- No new packages added.
- No changes to `AppLockService` crypto or storage layout.
- Brand palette preserved (primary, gold, charcoal).
- Inter font preserved throughout.
- No emoji.
