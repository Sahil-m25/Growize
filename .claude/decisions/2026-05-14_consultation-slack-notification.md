# 2026-05-14 — Slack notification on consultation request

## Problem
User wants a Slack ping when a `consultation_requests` row lands.

## Decision: DB-trigger → Edge Function (not direct client → Slack)

Two candidate patterns:

| Pattern | Pros | Cons |
|---|---|---|
| **Client posts to Slack** after the insert succeeds | Simplest — one fetch from the app. No new infra. | If the user closes the app between insert and post, the notification is dropped. Webhook URL has to live in client code or be exposed via an unauthenticated endpoint. |
| **DB trigger → Edge Function → Slack** (chosen) | pg_net retries up to a minute, so the post survives client disconnect. Webhook URL stays server-side. Same shared-secret + Vault pattern already in use by gallery-sync / health-check / sync-stale-alert. | One more edge function to deploy + one more env var to set. |

The whole point of the notification is for ops to follow up — losing one because the user backgrounded the app would defeat that. Robustness wins.

## How it fits together
1. Client inserts a row into `public.consultation_requests` (RLS-scoped — investor inserts their own only).
2. `AFTER INSERT` trigger fires `notify_consultation_request()`. It reads `cron_secret` from Vault and `pg_net.http_post`s `{consultation_request_id: <id>}` to the edge function with `x-arl-cron-secret` header.
3. Edge function validates the secret, fetches the row + project + investor (service-role), and POSTs a formatted block payload to `SLACK_CONSULTATION_WEBHOOK_URL`.
4. If `SLACK_CONSULTATION_WEBHOOK_URL` is unset, the function logs a warning and returns 200 — never failing the trigger.

## Files
- `supabase/functions/notify-consultation-request/index.ts` (new)
- `supabase/migrations/20260514000000_037_consultation_slack_trigger.sql` (new)

## Deployment checklist (run by user / orchestrator)
1. Set Supabase function env vars:
   - `SLACK_CONSULTATION_WEBHOOK_URL` = `<https://hooks.slack.com/...>` (user provides)
   - `CRON_SECRET` = current value of `vault.secrets.cron_secret` (already in Vault, see migration 016)
2. Deploy: `supabase functions deploy notify-consultation-request --no-verify-jwt`
3. Apply migration 037

## Open questions
- Slack webhook URL not provided yet. Function ships safe (no-op when env missing) so this can land before the URL is wired.
- We reuse `cron_secret` from migration 016 to avoid a new credential. If we ever need per-function rotation we can add `consultation_notify_secret`.
- Investor lookup uses `public.investors.user_id` — verified the table exists (migration 001). Edge function falls back to "Unknown investor" if no row.
