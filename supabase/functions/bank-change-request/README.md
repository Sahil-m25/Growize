# bank-change-request

P1 — investor requests a payout-bank change. 7-day cooldown.

```bash
supabase functions deploy bank-change-request
```

Body:

```json
{
  "bank_name": "HDFC Bank",
  "account_masked": "XXXX-XXXX-5678",
  "ifsc": "HDFC0001234",
  "holder_name": "Rahul Sharma"
}
```

Returns `{ "request_id": "uuid" }`. Investor side never sees the unmasked account number — the masked form is what's stored.

Note: this function does NOT update the live bank details. Staff must approve in CRM (or future admin tool) and the row in `bank_change_requests` flips to `approved`.
