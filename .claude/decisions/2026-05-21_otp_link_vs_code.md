# OTP email contains magic link instead of 6-digit code

**Date:** 2026-05-25
**Status:** locked (server-side OK; awaits one manual Dashboard edit)
**Linked work:** decisions/2026-05-21_otp_auth_refactor.md

## Symptom

User taps "Send Code" -> email arrives, but it contains a clickable magic
link rather than a 6-digit code. The Flutter OTP screen expects a token
that fits into 6 input boxes and calls
`Supabase.instance.client.auth.verifyOTP(token: ..., type: OtpType.email)`,
so pasting a URL fails.

## Investigation

### 1. Edge function (deployed v5, project `oynfhdqizebvgmaoiuax`)

Retrieved via `mcp__supabase__get_edge_function`. The OTP send is a raw
HTTP POST to `/auth/v1/otp`:

```ts
const otpBody: Record<string, unknown> = { create_user: false };
if (channel === "email") {
  otpBody.email = investor.email;
} else {
  otpBody.phone = investor.phone;
}

const r = await fetch(`${SUPABASE_URL}/auth/v1/otp`, {
  method: "POST",
  headers: { "Content-Type": "application/json", apikey: ANON_KEY },
  body: JSON.stringify(otpBody),
});
```

There is **no** `redirect_to` / `email_redirect_to` anywhere in the body
or headers. That is the correct shape for a pure-token OTP request.

Conclusion: **the function is not the cause.**

Also noticed: the local file
`supabase/functions/request-auth-email/index.ts` was the previous
SDK-style version (used `auth.signInWithOtp`). Deployed v5 is the
raw-fetch version. To prevent a future deploy from regressing the
function, the local file was overwritten to match v5 verbatim (with a
header comment documenting why `redirect_to` is omitted).

### 2. Auth email template

`auth.config` does not exist in this project -- GoTrue stores its config
outside Postgres, so the template body cannot be read via the SQL or
Management MCP tools available here. The only places to inspect or edit
it are:

- Supabase Dashboard -> Authentication -> Email Templates -> **Magic Link**
- Management API `PATCH /v1/projects/{ref}/config/auth` (would need an
  admin PAT, not provided)

Given the function is correct and the email still contains a link, the
template must still reference `{{ .ConfirmationURL }}` (Supabase's
default) rather than `{{ .Token }}`. This is the **only remaining
explanation**.

## Decision

**Root cause:** Supabase Magic Link email template still uses the default
`{{ .ConfirmationURL }}` placeholder. The template has to be edited by
hand in the Dashboard -- no programmatic path with the MCP scope on
record here.

**Server-side fixes applied:**
- Synced `supabase/functions/request-auth-email/index.ts` to match the
  deployed v5 (was stale).
- Added an explicit comment block in the function source explaining the
  `redirect_to` omission, so any future maintainer doesn't reintroduce
  it thinking it's missing.

**Dashboard fix the user must do:**
Supabase Dashboard -> Authentication -> Email Templates -> **Magic Link**.

Replace **Subject**:
```
Your Growize sign-in code
```

Replace **Message body** with:
```
Your Growize sign-in code is: {{ .Token }}

This code expires in 1 hour. If you didn't request this, you can
ignore this email.

-- ARL Tech
```

Save. Templates take effect immediately, no redeploy needed.

## Verification

1. Open app -> enter a registered investor email -> tap Send Code.
2. New email should arrive with subject "Your Growize sign-in code"
   and a 6-digit number in the body (no clickable link).
3. Type the 6 digits into the OTP screen -> continue.
4. App calls `auth.verifyOTP(token: '123456', type: OtpType.email)` ->
   session opens, biometric/PIN setup pages follow.

If step 2 still shows a link after the template edit, the template
wasn't saved -- re-open the editor in the Dashboard and confirm the
preview pane shows the code rather than a URL.

## Why this took two passes

The earlier OTP refactor (`2026-05-21_otp_auth_refactor.md`) flagged
the template change as a manual TODO. That step was missed, hence
this follow-up. No code on either side was wrong -- the email shape
is entirely template-driven once `redirect_to` is omitted.
