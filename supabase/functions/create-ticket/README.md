# create-ticket

P1 — investor creates a support ticket. Rate limited to 5 / 24h.

## Deploy

```bash
supabase functions deploy create-ticket
```

(JWT verification is on by default — Supabase will reject calls without an investor JWT.)

## Required Vault secrets

- `ARL_OPS_EMAIL` — destination for the new-ticket notification.
- `RESEND_API_KEY` — outbound email provider.

## Body

```json
{
  "category": "payout",          // payout | documents | general | bank_change | exit_request
  "subject": "Payout not received for March",
  "body": "I was expecting my payout by March 31st...",
  "project_id": "uuid-optional"
}
```

## Responses

- `200` — `{ "ticket_id": "uuid" }`
- `400` — body validation
- `401` — no JWT
- `429` — rate-limited (5 / 24h)
- `500` — DB or email failure
