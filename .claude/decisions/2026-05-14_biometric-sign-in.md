# 2026-05-14 — Biometric sign-in for returning users

## Problem
UAT: users who'd enabled biometric in Security still had to type email + password on every cold start. No way to invoke biometric from the login screen.

## Decision
Added a biometric button on the login screen, gated by three local conditions:
1. `flutter_secure_storage` flag `arl.auth.biometric_enabled = 'true'` (mirrored from `user_settings.biometric_enabled`)
2. A cached refresh token in secure storage
3. `BiometricGuard.isAvailable()` reports the device can prompt

## Why not query Supabase first
Querying `user_settings` for the flag requires an authenticated session — chicken-and-egg. Mirroring the flag locally means the login screen renders the button instantly with no network round-trip.

## Cache lifecycle
- Written by `authStateProvider` on every `signedIn` / `tokenRefreshed` event, but only when the user's `user_settings.biometric_enabled` is true. If it flips false on another device, the next refresh on this device clears the cache automatically.
- Written by `SecurityScreen._setBiometric` when the toggle goes on, cleared when it goes off.
- Cleared on `signedOut`.
- Cleared on `AuthException` from `setSession` (token revoked / expired).

## New code
- `lib/core/auth/secure_session_store.dart` — `SecureSessionStore` wrapping `flutter_secure_storage` with three keys: `last_email`, `refresh_token`, `biometric_enabled`.
- `SessionManager.signInWithRefreshToken(String)` — wraps `client.auth.setSession(refreshToken)`.

## Files changed
- `pubspec.yaml` — add `flutter_secure_storage: ^9.2.2`
- `lib/core/auth/session_manager.dart`
- `lib/core/auth/secure_session_store.dart` (new)
- `lib/features/auth/auth_provider.dart`
- `lib/features/auth/login_screen.dart`
- `lib/features/profile/security_screen.dart`

## Verification
`dart analyze lib` clean. Cannot manually exercise biometric in this worktree (no device). Logic verified by reading control flow.

## Open question
On web, `flutter_secure_storage` uses `localStorage` with a per-origin AES key. That's fine for our UAT context. If we ship to native we get OS keychain backing automatically — no code change.
