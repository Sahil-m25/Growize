# reply-ticket

P1 — investor adds a reply to their own ticket. Blocked if ticket is `resolved`.

```bash
supabase functions deploy reply-ticket
```

Body:

```json
{ "ticket_id": "uuid", "body": "Following up on this..." }
```

Returns `{ "message_id": "uuid" }`.
