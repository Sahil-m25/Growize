# onboard-investor

P0 — invites a new investor and creates the matching `investors` row.

## Deploy

```bash
supabase functions deploy onboard-investor --no-verify-jwt
```

`--no-verify-jwt` because there is no user session yet — the caller is ARL staff using the admin secret.

## Required Vault secrets

- `ADMIN_SECRET` — checked against the inbound `X-ARL-Admin-Secret` header.

## Call

```bash
curl -X POST 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor' \
  -H 'X-ARL-Admin-Secret: <ADMIN_SECRET>' \
  -H 'content-type: application/json' \
  -d '{
    "email": "investor@example.com",
    "name": "Rahul Sharma",
    "arl_id": "ARL-00143",
    "zoho_contact_id": "1169101000001292001",
    "phone": "9876543210",
    "salutation": "Mr."
  }'
```

## Responses

- `200` — `{ investor_id, arl_id, message }`. Supabase has emailed the password-set link.
- `400` — body validation failed.
- `401` — admin secret mismatch.
- `409` — investor already exists for this email.
- `500` — Supabase auth or insert failed.
