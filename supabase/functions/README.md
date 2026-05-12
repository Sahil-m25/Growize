# Edge Functions

| Function | Priority | Auth | JWT verify | Purpose |
|---|---|---|---|---|
| `onboard-investor` | P0 | `X-ARL-Admin-Secret` | off | ARL staff invites a new investor |
| `zoho-crm-webhook` | P0 | `X-ARL-Webhook-Secret` | off | Mirrors Zoho CRM modules into Supabase |
| `create-ticket` | P1 | Investor JWT | on | Creates a support ticket |
| `reply-ticket` | P1 | Investor JWT | on | Replies to an own ticket |
| `bank-change-request` | P1 | Investor JWT | on | Submits a payout-bank change request |
| `gallery-sync` | P1 | none (cron) | off | Daily pull of Zoho attachments → `arl-gallery` |
| `zoho-books-webhook` | P2 | — | — | **Deferred** until Zoho Books is connected |

## Deploy all (P0 + P1)

```bash
supabase login
supabase link --project-ref oynfhdqizebvgmaoiuax

supabase functions deploy onboard-investor --no-verify-jwt
supabase functions deploy zoho-crm-webhook --no-verify-jwt
supabase functions deploy gallery-sync --no-verify-jwt
supabase functions deploy create-ticket
supabase functions deploy reply-ticket
supabase functions deploy bank-change-request
```

## Required Vault secrets

```bash
# Generate strong secrets:
#   openssl rand -hex 16
supabase secrets set ADMIN_SECRET=<32 hex>
supabase secrets set WEBHOOK_SECRET=<32 hex>

# Zoho OAuth — only needed for gallery-sync.
supabase secrets set ZOHO_CLIENT_ID=...
supabase secrets set ZOHO_CLIENT_SECRET=...
supabase secrets set ZOHO_REFRESH_TOKEN=...

# Email (Resend) — only for create-ticket / reply-ticket / bank-change-request.
supabase secrets set ARL_OPS_EMAIL=ops@agresearchlabs.com
supabase secrets set RESEND_API_KEY=re_xxx
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by the Functions runtime — don't set those.

## Local development

```bash
supabase functions serve --env-file ./supabase/.env.local
```

`./supabase/.env.local` (NOT committed) should contain the same keys you'd put in Vault, prefixed with `SUPABASE_*` overrides if you want to point at a branch DB.
