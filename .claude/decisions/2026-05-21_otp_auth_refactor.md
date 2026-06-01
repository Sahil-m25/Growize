# 2026-05-21 — Replace password auth with email OTP

## Status

Implemented. Edge function CHANGE NOT REQUIRED — but Supabase Auth
"Magic Link" email template MUST be updated to deliver the 6-digit
`{{ .Token }}` value (see "Edge function verdict" below) before this
ships to production.

## Context

The previous login flow asked for email + password and offered a
"Forgot password?" recovery link. The recovery branch had been
unreliable for weeks (see `2026-05-21_forgot_password_diag.md`) and
the password input itself adds zero security for an invite-only
investor portal where every email is gated through
`request-auth-email` already. Users were also reaching out asking to
"just have a code sent" — the password was actively friction.

Decision: kill the password flow entirely and replace it with email
OTP. Biometric / PIN app-lock continues to be the second factor on
device.

## What changed

### Files added

- `lib/features/auth/otp_screen.dart` — 6-digit code entry, auto
  advance / paste-to-fill, resend with 60s cooldown, change-email
  link, inline error display. Routes to `/home` or
  `/setup-biometric` after verify based on
  `user_settings.biometric_enabled`.
- `lib/features/auth/setup_biometric_screen.dart` — one-screen
  post-login nudge to enable biometric. Reuses the
  `AppLockController.setBiometricEnabled` path (including the PIN
  fallback prompt) and mirrors the flag to `user_settings` so future
  logins skip the screen.

### Files modified

- `lib/features/auth/login_screen.dart` — full rewrite. Single email
  field, "Send Code" button (disabled when empty or invalid),
  "Trouble logging in? Contact support" footer linking to
  `wa.me/{kTechPhone}`. No password field, no Forgot Password modal,
  no Sign Up link. Phone-OTP toggle intentionally not wired yet; the
  layout is structured (`_buildEmailChannel`) so adding it later is
  a small swap.
- `lib/core/auth/session_manager.dart` — removed
  `signInWithEmailPassword`, `requestPasswordReset`,
  `updatePassword`. Kept `signInWithOtp` (used by `sendCode` /
  Resend), `verifyEmailOtp`, `signOut`, `signInWithRefreshToken`.
- `lib/core/navigation/router.dart` — registered `/otp` (public,
  takes `extra: email`) and `/setup-biometric` (private). Comment
  rewritten to refer to `verifyOTP` instead of `signInWithPassword`.
- `lib/core/navigation/route_names.dart` — `otp = '/otp'`,
  `setupBiometric = '/setup-biometric'`.

### Files deleted

None. All password code lived inline in the rewritten
`login_screen.dart` and the now-deleted SessionManager methods. No
recovery-link deep-link handlers existed in `lib/` (grep for
`access_token` / `PasswordRecovery` confirmed clean).

## Edge function verdict

`supabase/functions/request-auth-email/index.ts` currently handles
two `mode` values:

- `mode: 'reset'` -> `supabase.auth.resetPasswordForEmail` (recovery
  link, not a 6-digit OTP). The Flutter app no longer calls this.
- `mode: 'magic_link'` -> `supabase.auth.signInWithOtp({ email,
  options: { shouldCreateUser: false } })`. This is the path the
  refactored app uses.

`signInWithOtp` makes Supabase issue BOTH a magic link AND a 6-digit
OTP token in the same email. Which one the user sees depends on the
"Magic Link" email template in **Supabase Dashboard -> Authentication
-> Email Templates**. The default template renders only
`{{ .ConfirmationURL }}` — that template must be updated to include
`{{ .Token }}` (the 6-digit code) so users can type it into
`OtpScreen`. `verifyOTP({ type: OtpType.email })` on the client will
then succeed.

**Follow-up for the user (not a code change):**

1. Open Supabase Dashboard -> Authentication -> Email Templates ->
   Magic Link.
2. Replace (or supplement) the existing body so the email shows the
   6-digit token. A minimum example:

   ```
   <p>Your Growize sign-in code is:</p>
   <p style="font-size:24px; font-weight:600; letter-spacing:4px;">
     {{ .Token }}
   </p>
   <p>This code expires in 1 hour.</p>
   ```

3. Save. No edge function redeploy needed; no Flutter rebuild
   needed.

If we later want to *remove* the magic-link URL entirely (so a
shoulder-surfer who sees the email cannot click their way in), drop
the `{{ .ConfirmationURL }}` reference from the same template.

The legacy `mode: 'reset'` branch is now unused but kept in the
edge function — pruning it is safe but not urgent.

## What did not change

- `request-auth-email` edge function (read-only — flagged template
  update above).
- LockScreen / AppLockService / Security screen biometric toggle.
- KYC / projects / financials / gallery / docs.
- Logout button (still `supabase.auth.signOut()`).
- Biometric enrolment logic (`AppLockController.setBiometricEnabled`).

## Verify

```
& C:\flutter\bin\dart.bat analyze lib
& C:\flutter\bin\flutter.bat pub get        # only if pubspec changed (it did not)
& C:\flutter\bin\flutter.bat run -d chrome  # web smoke
& C:\flutter\bin\flutter.bat run -d <device-id>  # android smoke
```

### Per-platform test sequence

- **Android:** `flutter run -d <device-id>`. Sign out if logged in.
  1. Land on `/auth`, tap Sign In -> `/login`.
  2. Enter email, Send Code -> toast appears, screen navigates to
     `/otp` with masked email visible.
  3. Type the 6-digit code from email -> verify lands on
     `/setup-biometric` (first login) OR `/home` (subsequent).
  4. On `/setup-biometric` -> Set up now -> prompted for new PIN ->
     biometric prompt -> home. Force-quit app and reopen ->
     LockScreen prompts biometric.
  5. Wrong code path: type 6 random digits -> inline earth-coloured
     "Wrong code, try again", boxes clear, focus returns to box 1.
  6. Expired code path: wait > 1 hour, type old code -> "Code
     expired, tap Resend". Tap Resend (after 60s cooldown elapses)
     -> new code arrives.
  7. Contact support link -> opens WhatsApp to tech number with
     prefilled message.

- **Web:** `flutter run -d chrome`.
  1. Same steps 1-3 as Android.
  2. `/setup-biometric` shows the same UI but tapping Set up now
     surfaces the "not supported on web" snackbar — user can Skip
     to reach home.
  3. LockScreen does not fire (web has no `local_auth` backend).

## Rebuild commands the user needs to run

```
& C:\flutter\bin\flutter.bat pub get
& C:\flutter\bin\dart.bat analyze lib
& C:\flutter\bin\flutter.bat run -d chrome    # quick smoke
# Mobile release builds:
& C:\flutter\bin\flutter.bat build apk --release
& C:\flutter\bin\flutter.bat build ios --release
```

If the template update is made in the Supabase Dashboard, no app
rebuild is required for that change to take effect — it is a
server-side asset.
