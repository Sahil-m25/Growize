# BiometricScreen wiring

**Date:** 2026-05-12
**Phase:** Implement
**Status:** locked

## Problem
Audit row `BiometricScreen (biometric_screen.dart)` in
`ARL_Test_Tracker.xlsx` sheet `Flutter Feature Audit` was Fail — the
screen existed under `lib/features/auth/` but was not registered in
the router, so no call site could ever reach it.

## Decision
Keep the screen. Wire it as an **enrollment/confirmation gate** for
the SecurityScreen Biometric Login toggle.

- New route `RouteNames.biometric` = `/biometric`, registered at the
  top-level (outside the bottom-nav ShellRoute) so the verification
  screen renders full-bleed primary teal.
- `BiometricScreen` now pops with `true` on a passing biometric check,
  `false` on cancel. When pushed via `context.push<bool>(...)` callers
  await the result. Legacy "no stack" path still falls through to
  `go(RouteNames.home)` so the file is safe to reach standalone.
- `SecurityScreen._setBiometric`: when turning the toggle **on**,
  `context.push<bool>(RouteNames.biometric)` is awaited; only a `true`
  result persists `biometric_enabled=true`. Cancel/fail keeps the
  toggle off (and re-fetches `userSettingsProvider` so the switch
  snaps back). Turning the toggle **off** persists directly — a
  downgrade does not require a fresh biometric check.

## Why pop-with-bool over a separate route param
The existing screen state already had `_loading` + retry; adding a
`mode=enroll` param + branching would have grown surface area. The
`canPop`-aware `_exit` helper is one method, leaves the legacy entry
intact, and lets callers `await context.push<bool>(...)` naturally.

## Touched files
- `lib/core/navigation/route_names.dart` (added `biometric` const)
- `lib/core/navigation/router.dart` (registered `/biometric` route)
- `lib/features/auth/biometric_screen.dart` (return-result + Cancel button)
- `lib/features/profile/security_screen.dart` (gate biometric-on with push)

## Verification
- `dart analyze lib` — `No issues found!`
- Manual flow verification deferred to in-app QA (analyzer covers
  type/lint; physical biometric prompt requires a real device).

## Rollback
- Revert files listed above.
