# 2026-05-21 — Forgot password email not arriving (diag)

## TL;DR

**Not a code bug. SMTP isn't configured (or is rate-limited) on the
Supabase project.** The Flutter app, the `request-auth-email` Edge
Function, and the auth-gate flow are all wired correctly and the
function is being invoked. GoTrue is silently failing to send the
recovery email — no `auth.users.recovery_sent_at` row has been updated
for any user.

The fix is a one-time Supabase Studio config (custom SMTP, e.g.
Resend), not a code change.

## What we know

### (a) Code path on tap

`features/auth/login_screen.dart::_showForgotPasswordModal()` ->
`SessionManager.requestPasswordReset(email)` ->
`SessionManager._requestAuthEmail(email, mode: 'reset')` ->
`client.functions.invoke('request-auth-email', body, x-arl-cron-secret)`.

The app does **not** call `Supabase.instance.client.auth.resetPasswordForEmail`
directly. Every reset goes through our gate.

### (b) Edge function status

Function `request-auth-email` (id `07227048-...`, v3, `verify_jwt:false`)
is deployed and ACTIVE. Two POSTs landed today, both returning 200 in
**1.78 s** and **1.25 s**:

```
2026-05-23T15:55Z  POST /functions/v1/request-auth-email  200  1782 ms
2026-05-23T15:53Z  POST /functions/v1/request-auth-email  200  1249 ms
```

Important detail: those execution times are far above the 350 ms
no-op timing pad. That means the function passed both the shared-secret
gate AND the `investors.email -> user_id -> auth.users` lookup — so the
test email IS in the database and the function reached the
`supabase.auth.resetPasswordForEmail(email)` call.

### (c) GoTrue / SMTP status

```sql
SELECT email, recovery_sent_at FROM auth.users ORDER BY created_at DESC;
```

`recovery_sent_at` is **NULL for every user**. If GoTrue had
successfully generated and dispatched a recovery email even once,
this column would be populated.

GoTrue only stamps `recovery_sent_at` *after* a successful SMTP
hand-off. The function swallows the error from
`resetPasswordForEmail`'s `{error}` payload and still returns 200
to the caller (by design, so callers can't distinguish "unknown
email" from "send failed"). That's why the user sees the cheerful
"if registered, you'll get an email" snackbar even when nothing was
ever sent.

### (d) Why the send fails

Supabase's **built-in/default SMTP** (the one that's enabled when no
custom SMTP is configured) only sends to **team members of the
Supabase organization** and is hard-rate-limited to **4 messages /
hour project-wide**. It is explicitly documented as
"not for production" — tester emails to investor addresses are
dropped silently.

Without a custom SMTP provider configured under Authentication ->
Emails -> SMTP Settings, `resetPasswordForEmail` will keep returning
silent failures for every non-team-member address, exactly matching
what we're seeing.

## Verdict

| Layer | State |
|---|---|
| App code (`SessionManager.requestPasswordReset`) | Correct. No fix needed. |
| Edge function (`request-auth-email`) | Correct. Receives the call, runs the happy-path code, returns 200. |
| Supabase SMTP config | **Missing / default.** This is the root cause. |
| `AUTH_RESET_REDIRECT_URL` secret | Not currently set on the function (optional, but recommended so the link in the email lands on the prod app, not the Supabase placeholder). |

Root cause: **SMTP misconfiguration**, not a code bug.

## Action items

### Code fixes made

None. Confirmed by reading:

- `lib/features/auth/login_screen.dart` (modal -> `requestPasswordReset`)
- `lib/core/auth/session_manager.dart` (`requestPasswordReset` ->
  `_requestAuthEmail` -> `functions.invoke('request-auth-email')`)
- `lib/core/constants/supabase_constants.dart` (`fnRequestAuthEmail`
  + `authGateSecret` resolution works in both dart-define and
  dotenv modes)
- `supabase/functions/request-auth-email/index.ts` (passes secret
  gate, looks up investor, calls `auth.resetPasswordForEmail`)

The pipeline is wired exactly as the 2026-05-15 auth-gate decision
spec described. The fact that the function is actually being hit
(see logs above) and returning 200 with a happy-path latency
profile confirms it.

### Manual config the user must do

**1. Sign up at Resend (free 100 emails/day).** — `https://resend.com`

**2. Add and verify the sending domain.**

- Add domain `agresearchlabs.com` in Resend.
- Add the SPF + DKIM + DMARC DNS records Resend gives you to the
  registrar holding `agresearchlabs.com`.
- Wait until Resend shows the domain as **Verified** (usually a few
  minutes; can take up to an hour).

**3. Generate a Resend API key.** Scope: "Sending access" to the
   verified domain. Copy the key (you only see it once).

**4. Wire Resend into Supabase.**
   Supabase Dashboard -> Project -> **Authentication -> Emails -> SMTP
   Settings**:

   | Field | Value |
   |---|---|
   | Enable custom SMTP | **ON** |
   | Sender email | `noreply@agresearchlabs.com` |
   | Sender name | `Growize` |
   | Host | `smtp.resend.com` |
   | Port | `465` |
   | Username | `resend` |
   | Password | *(paste the Resend API key)* |
   | Minimum interval | `60s` (or higher; raises per-user throttle) |

   Click **Save**, then click **Send test email** — it should arrive
   within ~10 s.

**5. Bump the rate limits while you're there.**
   Authentication -> **Rate Limits** -> "Rate limit for sending emails":
   default is 4/hr (the built-in cap). With custom SMTP you can lift
   this. For an invite-only investor portal, 30/hr is a sensible
   ceiling.

**6. (Optional but recommended) Set the redirect URL secret on the
   Edge Function**, so the link inside the email opens the right
   place:

```sh
supabase secrets set AUTH_RESET_REDIRECT_URL=https://app.growize.in/reset \
  --project-ref oynfhdqizebvgmaoiuax
```

   Replace the URL with whichever app host you want the reset link
   to land on. Also ensure that host is in
   Authentication -> URL Configuration -> **Redirect URLs**, otherwise
   GoTrue will strip the redirect.

**7. Verify.** From the app, tap "Forgot password?", enter a real
   investor address, submit. Then:

```sql
SELECT email, recovery_sent_at FROM auth.users
WHERE email = '<the address you tested>';
```

   `recovery_sent_at` should now be a fresh timestamp. The email
   should arrive within ~15 s.

## How we'd catch this earlier next time

The function deliberately swallows the SMTP error to preserve
enumeration-resistance, but right now there is **no observable
signal** that the send failed beyond a missing
`auth.users.recovery_sent_at` row. Two options if we want to
detect this without breaking the security property:

- Have the function emit a structured `console.error` with
  `{stage:"smtp_send", code:error.status}` (it already does — but
  we should set up a log-based alert on it).
- Add a daily sanity check in `sync-stale-alert` (or similar)
  that pings the SMTP endpoint with a known-good address and
  alerts Slack if the response code isn't 200.

Neither is required for the immediate fix.

## Files inspected (no changes)

- `lib/features/auth/login_screen.dart`
- `lib/core/auth/session_manager.dart`
- `lib/core/constants/supabase_constants.dart`
- `supabase/functions/request-auth-email/index.ts`
- `.claude/decisions/2026-05-15_auth-gate-invite-only.md`

## Verification commands (Windows / PowerShell)

```powershell
& C:\flutter\bin\dart.bat analyze lib
```

Skipped — no `.dart` files were modified during this diagnosis.
