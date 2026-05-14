# Edge function CORS — restrict to allow-list — remediate S-005

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Audit finding:** S-005 (High) — `docs/security_audit_2026-05-13.md`

## Problem
Every browser-facing edge function shipped
`Access-Control-Allow-Origin: *` in its CORS preflight + response
headers. JWT + shared-secret gates still protect the call paths,
but a wildcard means any origin can present a preflight and any
origin gets the response — no defense in depth, and it surfaces
attack surface on any future endpoint that doesn't enforce
auth perfectly.

## Decision
Centralise CORS in `supabase/functions/_shared/cors.ts` and have
every browser-facing function import from it.

The shared helper exposes:
- `corsHeaders(req)` — reads `APP_ALLOWED_ORIGINS`
  (comma-separated env var), matches the request's `Origin` header
  against it, and echoes only the matched origin. Never `*`.
  Includes `Vary: Origin` so any caching layer keys on it.
- `preflight(req)` — returns a 200 OPTIONS response with the
  computed headers, or `null` for non-OPTIONS requests.
- `jsonResponse(req, body, init?)` — replaces each function's
  local `jsonResponse(body, init?)`. Takes `req` first so it can
  call `corsHeaders(req)`.

Localhost wildcard support: a pattern like `http://localhost:*` in
the allow-list matches any port. Lets `flutter run -d chrome`
(which picks a random debug port each launch) work without manual
re-config.

Server-to-server callers (Zoho webhook, pg_cron, Supabase
scheduled functions) don't send `Origin` — the helper omits
`Allow-Origin` entirely in that case, which is fine because CORS
only applies in a browser.

The earlier "self-contained on purpose" comment in each function
header was reversed for this fix — relative `../_shared/cors.ts`
imports deploy correctly with `supabase functions deploy <name>`,
and the duplicated CORS boilerplate was actively a liability for
this kind of security-policy change.

## Touched files
- `supabase/functions/_shared/cors.ts` (rewritten — origin-aware allow-list, exports corsHeaders/preflight/jsonResponse)
- `supabase/functions/bank-change-request/index.ts` (drop local cors + jsonResponse, import shared, inject `req`)
- `supabase/functions/create-ticket/index.ts`        (same)
- `supabase/functions/onboard-investor/index.ts`     (same)
- `supabase/functions/reply-ticket/index.ts`         (same)
- `supabase/functions/zoho-crm-webhook/index.ts`     (same)

Cron-only functions (`health-check`, `sync-stale-alert`,
`zoho-reconcile-daily`, `gallery-sync`) had no CORS to begin with
(they reject anything that isn't a shared-secret POST) — not
touched.

## Ops follow-up — required before deploy
1. Set the allow-list secret:
   ```
   supabase secrets set APP_ALLOWED_ORIGINS=https://app.agresearchlabs.com,http://localhost:*
   ```
   Replace the production origin with whatever the real web build
   serves on once that's nailed down. The localhost-wildcard entry
   is for `flutter run -d chrome` during dev.

2. Deploy each affected function one at a time:
   ```
   supabase functions deploy bank-change-request
   supabase functions deploy create-ticket
   supabase functions deploy onboard-investor
   supabase functions deploy reply-ticket
   supabase functions deploy zoho-crm-webhook
   ```
   The `--no-verify-jwt` flag (where it was set before) is unchanged
   — confirm against the function's existing deploy command in the
   header comment of each file.

3. Smoke test from an allowed origin (Flutter web build or
   `http://localhost:<port>`):
   - Send a preflight `OPTIONS /functions/v1/create-ticket` with
     `Origin: http://localhost:8080`. Response must include
     `Access-Control-Allow-Origin: http://localhost:8080`
     (NOT `*`).
   - Send the same preflight with `Origin: https://attacker.example`.
     Response must have NO `Access-Control-Allow-Origin` header —
     browser blocks the subsequent request.

## Rollback
- Revert the shared `cors.ts` to the previous `*`-emitting version
  AND revert the 5 function index.ts files.
- OR set `APP_ALLOWED_ORIGINS=` to a single trusted origin
  temporarily and ship the dev-loop fix later.

Do not roll back by re-adding `*` to the allow-list — `*` is not
a valid origin pattern in the new helper and would simply match
nothing.
