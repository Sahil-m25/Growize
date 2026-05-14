# 2026-05-14 — One-tap sign-in + remove invite-violating signup buttons

## Problem
UAT: typing email/password and tapping Sign In once bounced user back to `/auth`. Second tap succeeded.

## Root cause
`router.dart` redirect read `ref.read(isLoggedInProvider)`. `isLoggedInProvider` is a `Provider` that watches `authStateProvider` (a StreamProvider). After `signInWithPassword` resolved, `SessionManager.isLoggedIn` returned true immediately, but the Riverpod `Provider` value was still cached at `false` because `authStateProvider` had not yet emitted the `signedIn` event downstream. When `context.go(home)` ran in `_signInPassword`, the redirect read cached `false` → bounced to `/auth`. Second tap saw cache refreshed → went through.

Enter key: no Form + no `onSubmitted`, so Enter did nothing — user thought it failed, then re-clicked button.

## Fix
1. `router.dart` `redirect:` now reads `SessionManager.isLoggedIn` directly (synchronous read of `currentUser != null`). Riverpod cache lag bypassed. `refreshListenable` still wired to auth stream so signOut continues to trigger redirect.
2. `login_screen.dart` password stage wrapped in a `Form` with `onFieldSubmitted` on the password field → invokes `_signInPassword` on Enter.
3. After `signInWithEmailPassword` await resolves, `ref.invalidate(isLoggedInProvider)` forces provider refresh so other watchers update without waiting on stream lag. (Converted to `ConsumerStatefulWidget`.)
4. `auth_screen.dart`: removed "New Investor — Get Started" outlined button. Re-centered "Sign In" button + Terms line vertically.
5. `login_screen.dart`: removed footer "New investor? Get started" `TextButton` (same invite-only violation).

## Files changed
- `lib/core/navigation/router.dart`
- `lib/features/auth/login_screen.dart`
- `lib/features/auth/auth_screen.dart`

## Verification
- `dart analyze lib` clean.
- Manual: cannot run flutter on this worktree (orchestrator policy). Verified via static analysis + code review of the new control flow.
