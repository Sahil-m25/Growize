# 2026-05-15 — Server-side auth-email gate (invite-only)

## Problem

`Supabase.instance.client.auth.resetPasswordForEmail(...)` and
`auth.signInWithOtp(...)` happily send mail to **any** address. For an
invite-only investor portal this is wrong twice over:

1. **Account enumeration.** A visitor can tell whether `x@y.com` is
   registered by observing whether an email arrives (or, on some flows,
   by latency / different success messages).
2. **SMTP / abuse.** Anyone can burn our Supabase SMTP quota by spraying
   the endpoint with random addresses.

## Decision

All outbound auth-email flows (password reset, magic link) now route
through a new Edge Function `request-auth-email` that:

1. Verifies a shared-secret header (`x-arl-cron-secret`).
2. Looks up the address in `public.investors` AND confirms the linked
   `auth.users` row exists (service role; bypasses RLS).
3. **Only if both exist** triggers the matching Supabase Auth flow —
   `resetPasswordForEmail` or `signInWithOtp({shouldCreateUser: false})`.
4. **Otherwise** sleeps a constant ~350 ms and returns 200 anyway, so
   the caller cannot distinguish "unknown email" from "sent" via either
   status code, response body, or latency.
5. **Never** logs the cleartext email — no "probed addresses" log
   surface is created.

The Flutter client (`SessionManager.requestPasswordReset` /
`SessionManager.signInWithOtp`) calls this function and surfaces a
uniform message to the user regardless of the underlying result:

> *"If `<email>` is registered, you will get an email shortly. Check your inbox."*

## Why a separate secret (`ARL_AUTH_GATE_SECRET` ≠ `CRON_SECRET`)

`CRON_SECRET` is shared with DB-trigger-fired functions
(`notify-consultation-request`, `sync-stale-alert`, etc.). Embedding
that value inside the Flutter binary would mean every shipped app
contains a key that can also fire DB-trigger workloads. Splitting the
secret limits the blast radius if a binary is reverse-engineered: a
leaked auth-gate secret only allows hitting the auth-gate endpoint
(which itself only sends mail to addresses that are already in the
investors table — so impact is bounded to "spam known investors").

## What the user MUST do in Supabase Studio

These toggles are **not** in code — they must be flipped manually in the
Supabase dashboard:

1. **Authentication → Providers → Email** — set
   **"Allow new users to sign up"** = **OFF** ("Disable signups").
   This is the master kill-switch; without it, `signInWithOtp` could
   still create users even though we pass `shouldCreateUser: false`
   via the SDK (defence in depth).
2. **Authentication → Providers → Email** — leave **"Confirm email"**
   ON. (Already the default.)
3. **Authentication → URL Configuration** — verify **Site URL** is the
   production app URL so `resetPasswordForEmail` links land on the
   correct host. Add any additional dev / preview hosts to
   **Additional Redirect URLs**.
4. **Authentication → Rate Limits** — set sensible per-IP / per-email
   ceilings on "Sign-ups and password recovery" (default 30/hr is
   usually fine, but lower is safer for invite-only).

## Files changed

- `supabase/functions/request-auth-email/index.ts` *(new)* — the gate.
- `lib/core/constants/supabase_constants.dart` — `fnRequestAuthEmail`
  + `authGateSecret` getter (reads `ARL_AUTH_GATE_SECRET` from
  dart-define or bundled `.env`).
- `lib/core/auth/session_manager.dart` — `requestPasswordReset` and
  `signInWithOtp` now POST to the Edge Function instead of calling
  the Supabase Auth SDK directly.
- `lib/features/auth/login_screen.dart` — forgot-password modal copy
  + snackbar updated to the neutral "if registered" wording.

## Env vars

| Where | Name | Notes |
|---|---|---|
| Flutter (`.env` / dart-define) | `ARL_AUTH_GATE_SECRET` | Same value baked into client. Rotate by re-shipping. |
| Edge Function (Supabase secrets) | `ARL_AUTH_GATE_SECRET` | Must match the client value byte-for-byte. |
| Edge Function (optional) | `AUTH_RESET_REDIRECT_URL` | Where the reset link lands. Falls back to the project's Site URL when unset. |

The function also reads the standard `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` injected automatically by the Edge runtime.

## Deploy

```sh
supabase functions deploy request-auth-email --no-verify-jwt
supabase secrets set ARL_AUTH_GATE_SECRET=<random 32+ char value>
# Optional:
supabase secrets set AUTH_RESET_REDIRECT_URL=https://app.growize.example/reset
```

The `--no-verify-jwt` flag is required because the function runs while
the user is signed-out (forgot-password / magic-link).

## What is **not** changed

- **`signInWithPassword`** is untouched. Supabase already returns the
  same `invalid_credentials` error for both "wrong email" and "wrong
  password", so it is not an enumeration vector.
- **Signup UI** was already removed; no further client change.
- **Biometric / refresh-token sign-in** routes are unaffected — they
  never sent mail in the first place.

## Verification

- `dart analyze lib` — clean.
- The function returns 200 with `{ok:true}` for both registered and
  unregistered emails; latency difference < 100 ms in local tests.
- No cleartext email is written to `console.log` anywhere in the
  function source (`grep -n console.log supabase/functions/request-auth-email/index.ts`
  confirms only error-shape and code-level logging).
