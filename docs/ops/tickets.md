# Support Tickets — Ops Reference

This doc tells ops everything they need to know about the support ticket pipeline:
the tables, the RLS, the edge functions investors call, the trigger that lights up
the bell on the investor side, and the SQL recipes you actually need at your desk.

Written against the schema as of migration 034 (2026-05-13). If something below
doesn't match what Studio shows you, verify against the live DB before acting —
this guide gets stale.

Cross-references:
- `docs/ops_admin_guide.md` Part 9 — notification triggers (overlap intentional).
- `supabase/migrations/20260411074932_006_notifications_support_bank.sql` — table DDL.
- `supabase/migrations/20260513040000_034_notification_triggers.sql` — bell-fire trigger.
- `supabase/functions/create-ticket/index.ts` and `.../reply-ticket/index.ts`.
- `lib/features/support/` — investor-side UI (Flutter).

---

## 1. Mental model

```
 ┌─────────────────────┐                                          ┌──────────────────┐
 │ Investor (Flutter)  │                                          │ Ops (Studio)     │
 │  /support           │                                          │  SQL editor      │
 └─────────┬───────────┘                                          └────────┬─────────┘
           │ tap "Raise a Ticket"                                          │
           │   ↓                                                           │
           │ POST functions/v1/create-ticket                               │
           │   body: {category, subject, body, project_id?}                │
           │   auth: investor JWT                                          │
           ▼                                                               │
 ┌─────────────────────┐                                                   │
 │ create-ticket fn    │   service-role, rate-limited 5/24h                │
 │  (Edge Function)    │   verifies JWT, INSERTs ticket + 1st message,     │
 │                     │   emails ops@agresearchlabs.com via Resend        │
 └─────────┬───────────┘                                                   │
           │ INSERT support_tickets (investor_id, subject, category,       │
           │                         status='open')                        │
           │ INSERT ticket_messages (sender_type='investor', body)         │
           ▼                                                               │
 ┌─────────────────────┐                                                   │
 │ support_tickets     │◄──────────────────────────────────────────────────┤  UPDATE status
 │ ticket_messages     │◄──────────────────────────────────────────────────┤  INSERT staff reply
 └─────────┬───────────┘                                                   │
           │ trg_notify_ticket_reply AFTER INSERT on ticket_messages       │
           │   WHEN NEW.sender_type <> 'investor'                          │
           ▼                                                               │
 ┌─────────────────────┐                                                   │
 │ notifications row   │                                                   │
 │  type='ticket'      │                                                   │
 │  title='New reply…' │                                                   │
 │  metadata.ticket_id │                                                   │
 └─────────┬───────────┘                                                   │
           │                                                               │
           │   investor opens app                                          │
           ▼                                                               │
 ┌─────────────────────┐                                                   │
 │ Bell badge +        │                                                   │
 │ /support list +     │                                                   │
 │ /ticket/<id>        │ reply (optional) → POST reply-ticket fn ──────────┘
 └─────────────────────┘
```

Three things to remember:
1. Investors **never** write to `support_tickets` or `ticket_messages` directly —
   they go through the `create-ticket` and `reply-ticket` Edge Functions. The
   direct INSERT RLS policies were dropped in migration 017.
2. Ops writes happen in Studio. There is **no ops UI** today.
3. The "ding the investor" mechanism is purely the `trg_notify_ticket_reply`
   trigger on `ticket_messages` INSERT. As long as you insert a row with
   `sender_type='staff'`, the bell lights up. No second write needed.

---

## 2. Schema

### `public.support_tickets`

| Column         | Type        | Null | Default            | Notes                                                   |
|----------------|-------------|------|--------------------|---------------------------------------------------------|
| `id`           | uuid        | no   | `gen_random_uuid()`| PK.                                                     |
| `investor_id`  | uuid        | no   | —                  | FK → `investors(id)` ON DELETE CASCADE. = `auth.uid()`. |
| `project_id`   | uuid        | yes  | —                  | FK → `projects(id)` ON DELETE SET NULL. Often NULL.     |
| `category`     | text        | no   | `'general'`        | CHECK in `('payout','documents','general','bank_change','exit_request')`. |
| `subject`      | text        | no   | —                  | Investor-supplied, max 200 chars (enforced in edge fn). |
| `status`       | text        | no   | `'open'`           | CHECK in `('open','in_progress','resolved')`.           |
| `created_at`   | timestamptz | yes  | `now()`            |                                                         |
| `updated_at`   | timestamptz | yes  | `now()`            | Bumped by `reply-ticket` and migration 010's trigger.   |

Indexes:
- `support_tickets_pkey` on `id`.
- `idx_tickets_investor_status` on `(investor_id, status, created_at DESC)` —
  serves the My-Tickets list and the staff "open tickets per investor" filter.
- `idx_support_tickets_project_id` on `project_id`.

### `public.ticket_messages`

| Column        | Type        | Null | Default            | Notes                                                   |
|---------------|-------------|------|--------------------|---------------------------------------------------------|
| `id`          | uuid        | no   | `gen_random_uuid()`| PK.                                                     |
| `ticket_id`   | uuid        | no   | —                  | FK → `support_tickets(id)` ON DELETE CASCADE.           |
| `sender_type` | text        | no   | —                  | CHECK in `('investor','staff')`. Drives the bubble side in the UI and the bell trigger. |
| `body`        | text        | no   | —                  | Max 5000 chars (enforced in edge fns, NOT in DB).       |
| `created_at`  | timestamptz | yes  | `now()`            | Sorted ascending in the thread.                         |

Indexes:
- `ticket_messages_pkey` on `id`.
- `idx_ticket_messages_ticket` on `(ticket_id, created_at)`.

### Row-Level Security

RLS is **enabled** on both tables. Active policies (migration 018):

| Table             | Policy                                | CMD    | Role            | Qual                                                              |
|-------------------|---------------------------------------|--------|-----------------|-------------------------------------------------------------------|
| `support_tickets` | `support_tickets: read own rows`      | SELECT | `authenticated` | `investor_id = auth.uid()`                                        |
| `ticket_messages` | `ticket_messages: read via own tickets`| SELECT| `authenticated` | `ticket_id IN (SELECT id FROM support_tickets WHERE investor_id = auth.uid())` |

What this means in plain English:
- An investor can only ever SELECT their own tickets and the messages on those
  tickets.
- There are **no** INSERT / UPDATE / DELETE policies for either table for the
  `authenticated` role. Direct writes from the Flutter app are blocked.
- Ops uses the Studio SQL editor which runs as `service_role` (or `postgres`),
  which bypasses RLS. That's how staff messages get in.
- The `service_role` keys live in the Edge Function environment. Investors
  never see them.

---

## 3. Edge functions

### `create-ticket`

| Aspect          | Detail                                                                  |
|-----------------|-------------------------------------------------------------------------|
| When it fires   | Flutter `SupportRepository.createTicket()` → `client.functions.invoke('create-ticket', …)` |
| Auth            | Supabase JWT in `Authorization: Bearer <token>`. The fn calls `auth.getUser(token)` to resolve `investorId`. |
| Verify_jwt      | true                                                                    |
| Body shape      | `{ "category": "payout|documents|general|bank_change|exit_request", "subject": string≤200, "body": string≤5000, "project_id"?: uuid }` |
| Rate limit      | 5 tickets / 24h per investor (counted via service-role SELECT). 429 on breach. |
| Writes          | INSERT `support_tickets` (with `investor_id` forced to JWT user-id, `status='open'`). INSERT `ticket_messages` with `sender_type='investor'`. If the message INSERT fails, the ticket row is deleted (best-effort rollback). |
| Side effects    | Resend email to `ARL_OPS_EMAIL` (default `ops@agresearchlabs.com`). Email body is HTML-escaped. |
| Returns         | `{ "ticket_id": "<uuid>" }` on success.                                 |
| Common errors   | `401 unauthorized` (no/bad JWT); `400 invalid json`; `400 category must be one of …`; `400 subject is required`; `400 subject too long (max 200)`; `400 body too long (max 5000)`; `429 rate_limited`; `500 ticket insert failed`; `500 first-message insert failed`. |

### `reply-ticket`

| Aspect          | Detail                                                                  |
|-----------------|-------------------------------------------------------------------------|
| When it fires   | Flutter `SupportRepository.replyTicket()` from the ticket detail screen. |
| Auth            | JWT. Same pattern as create-ticket.                                     |
| Verify_jwt      | true                                                                    |
| Body shape      | `{ "ticket_id": uuid, "body": string≤5000 }`                            |
| Ownership check | SELECT the ticket by id; refuse if `ticket.investor_id != JWT user-id`. Returns the same `404 ticket not found` error to avoid leaking ticket existence. |
| Status guard    | Refuses with `400 ticket_resolved` if `status='resolved'`.              |
| Writes          | INSERT `ticket_messages` with `sender_type='investor'`. Bumps `support_tickets.updated_at` so the staff inbox sorts by recency. |
| Side effects    | Resend email to ops with the reply body.                                |
| Returns         | `{ "message_id": "<uuid>" }`.                                           |

Operational note: when Resend's `RESEND_API_KEY` is unset (e.g. local dev),
both functions log a warning and skip the email. The DB rows still get written.

---

## 4. Trigger: `trg_notify_ticket_reply`

Defined in migration `20260513040000_034_notification_triggers.sql`. The
companion function is `public.notify_ticket_reply()`, `SECURITY DEFINER`,
`search_path = public, pg_temp`.

Fire condition:
- `AFTER INSERT ON public.ticket_messages FOR EACH ROW`.
- The function early-returns when `NEW.sender_type = 'investor'`. So **any**
  insert with `sender_type='staff'` lights the bell — whether it's a reply
  to an existing investor message or the very first message on an
  ops-initiated ticket (see Recipe T-6).

What it INSERTs into `public.notifications`:

```
investor_id = support_tickets.investor_id  (looked up by NEW.ticket_id)
type        = 'ticket'
title       = 'New reply on your ticket'
body        = 'New reply on ticket #' || substr(ticket_id::text, 1, 8) || '.'
metadata    = jsonb_build_object(
                'ticket_id',   NEW.ticket_id,
                'message_id',  NEW.id,
                'sender_type', NEW.sender_type)
```

Idempotency: there is none. If you INSERT two `'staff'` messages, you get two
notifications. If you INSERT one and then `UPDATE` it, the trigger only fires
on INSERT, so no second notification (good).

Edge case: if the parent ticket was deleted between the INSERT and the trigger
firing, `v_investor_id` is NULL and the function returns silently without
raising — no orphan notification, no error to the caller.

The function is `SECURITY DEFINER` so it can INSERT into `notifications`
regardless of which role triggered the INSERT (Studio user, Edge Function
service role, etc.).

---

## 5. Flutter UI walkthrough

Source: `lib/features/support/`. Routes registered in `lib/core/navigation/`.

### `support_screen.dart` — `/support`

- Title: "Assistance". Cream background, charcoal title.
- "Raise a Ticket" button → `context.push('/new-ticket')`.
- "My Tickets" list. Loads via the `_ticketsProvider` `FutureProvider`, which
  calls `SupportRepository.myTickets()`:
  ```sql
  SELECT id, investor_id, project_id, category, subject, status, created_at, updated_at
  FROM support_tickets
  ORDER BY updated_at DESC;
  ```
  (RLS scopes to the caller's `investor_id`.)
- If the real list is empty, the screen falls back to `mockSupportTickets`
  with a yellow "Sample" badge so the design isn't a blank canvas during
  onboarding. This is purely cosmetic — no DB read.
- Each card shows the ticket id (full UUID, ugly — see Defect D-3 below),
  the subject, status pill (blue for open/in_progress, green for resolved),
  and `created_at` formatted `MMM dd, yyyy`.
- Tapping a card pushes `/ticket/<id>`.

### `new_ticket_screen.dart` — `/new-ticket`

- Three fields: Subject (max ~200), Category (dropdown, see mapping below),
  Description (multiline, max 5000).
- Category dropdown values are **user-facing labels**, mapped to the DB enum:
  | UI label           | DB enum     |
  |--------------------|-------------|
  | Payout Issue       | `payout`    |
  | Document Request   | `documents` |
  | Profile Update     | `general`   |
  | Technical Issue    | `general`   |
  | Other              | `general`   |
  Note: the `bank_change` and `exit_request` enum values are reachable from
  other flows (bank change / exit screens) and aren't surfaced in this
  dropdown. That's by design — those flows have their own dedicated screens.
- Submit calls `SupportRepository.createTicket(...)` which invokes the
  `create-ticket` Edge Function. On success: snackbar "Ticket submitted
  successfully" + `context.pop()`. On failure: snackbar "Failed to submit: <err>".

### `ticket_detail_screen.dart` — `/ticket/<id>`

- App bar shows subject + status pill (blue/orange/green per `_getStatusColor`).
- Loads two providers in parallel:
  - `ticketByIdProvider(id)` → `SELECT … FROM support_tickets WHERE id = $1`.
  - `ticketMessagesProvider(id)` → `SELECT … FROM ticket_messages WHERE ticket_id = $1 ORDER BY created_at ASC`.
- Messages render as bubbles. `sender_type='investor'` → right-aligned, cream
  background. `sender_type='staff'` → left-aligned, light-green background.
- Reply input is shown **only** when `status != 'resolved'`. When resolved,
  the input is replaced by a static "This ticket is closed" banner.
- Sending a reply calls `SupportRepository.replyTicket(ticketId, body)` →
  `reply-ticket` Edge Function. On 400 the snackbar reads "This ticket is
  closed"; on 404 it pops the screen and shows "Ticket not found".
- The detail screen does **not** invalidate the My-Tickets list when a status
  flip happens server-side. Investors must either pull-to-refresh (not wired
  yet — see Defect D-1) or reload the route. See live test results below.

### `ticket_provider.dart`

Tiny file. Just two `FutureProvider.family` definitions for the detail screen.

---

## 6. Live test results — 2026-05-15

All tests run against project `oynfhdqizebvgmaoiuax`. The Chrome session was
signed in as Sahil Mohite (`sahil.mohite@agresearchlabs.com`, investor id
`6d8b2dfa-9f3c-4065-88f4-6f1e627ee7ea`) — the test investor I was originally
pointed at (`27d3735e-…` / `ofclash98@gmail.com`) was not the active session,
so the test artifacts ended up on Sahil's account. All flows still exercise
identically.

### Test 1 — Investor creates a ticket via Flutter UI

1. `/support` shows two existing sample tickets (the mock fallback fired
   because Sahil's account had no real tickets yet).
2. Tap "Raise a Ticket" → `/new-ticket` form renders.
3. Filled Subject = "E2E ticket test 2026-05-15", Category = "Payout Issue"
   (→ `payout`), Description = "Investigation 1 walkthrough — please ignore."
4. Tap "Submit Ticket". Form shows a loading spinner, then pops back to
   `/support`.
5. `/support` now lists the new ticket at the top with status `open`.

DB confirmation:
```
ticket_id  = 5cc42e84-8b1a-4f15-8ad6-e42e515082cb
subject    = "E2E ticket test 2026-05-15"
category   = payout
status     = open
created_at = 2026-05-15 10:13:22 UTC
```
and the matching `ticket_messages` row:
```
message_id  = 813fd311-41b6-4666-a123-deb739d3133b
sender_type = investor
body        = "Investigation 1 walkthrough — please ignore."
```

Quirk worth noting: on the **first** submit attempt I clicked the bottom-nav
"Documents" tab by accident (the submit button and the nav bar overlap on
this viewport). The submit DID succeed in the background — the ticket landed
in the DB — but the user got bumped to `/documents` mid-snackbar and so
visually it looked like nothing happened. See Defect D-2.

### Test 2 — Ops staff reply via SQL

```sql
INSERT INTO ticket_messages (ticket_id, sender_type, body)
VALUES ('5cc42e84-8b1a-4f15-8ad6-e42e515082cb',
        'staff',
        'E2E staff reply 2026-05-15 — ignore')
RETURNING id, created_at;
-- id         = 3e02764f-e307-40b8-9179-14ce7b2f8c9e
-- created_at = 2026-05-15 10:14:55 UTC
```

`trg_notify_ticket_reply` fired:
```
notification_id = 835d6fa4-185c-4e68-bc6c-9518a50113d7
investor_id     = 6d8b2dfa-9f3c-4065-88f4-6f1e627ee7ea (ticket's investor)
type            = ticket
title           = New reply on your ticket
body            = New reply on ticket #5cc42e84.
metadata        = {"ticket_id": "5cc42e84-…", "message_id": "3e02764f-…", "sender_type": "staff"}
```

Confirmed via Chrome: after `F5` reload, the bell icon shows the red unread
dot. Tapping the ticket card opens `/ticket/<id>` which now renders TWO
bubbles: the investor's message on the right (cream) and the staff reply
on the left (green). Status pill still says "open" at this point.

### Test 3 — Status transitions via SQL

```sql
-- a) open → in_progress
UPDATE support_tickets SET status = 'in_progress'
  WHERE id = '5cc42e84-8b1a-4f15-8ad6-e42e515082cb';
```
Investor side: `/support` list still showed `open` until I hit `F5` (router-only
nav doesn't re-fire the FutureProvider — see Defect D-1). After reload the
status pill on the list and on the detail screen both flipped to
`in_progress` (orange in the detail header).

```sql
-- b) in_progress → resolved
UPDATE support_tickets SET status = 'resolved'
  WHERE id = '5cc42e84-8b1a-4f15-8ad6-e42e515082cb';
```
After `F5` the status pill flipped to `resolved` (green/accent) and the
reply text input disappeared, replaced by a centred "This ticket is closed"
banner. Posting via the dead UI is impossible from the front-end, and the
`reply-ticket` Edge Function also refuses with `400 ticket_resolved`.

The CHECK constraint enforces `status ∈ ('open','in_progress','resolved')`.
There is no `closed` or `awaiting_investor` value — don't invent them.

### Test 4 — FG-01 stopgap (ops-initiated ticket TO an investor)

To confirm whether ops can today initiate a ticket that's attributed to an
investor (no investor action required), I ran:

```sql
WITH new_t AS (
  INSERT INTO support_tickets (investor_id, category, subject, status)
  VALUES ('6d8b2dfa-9f3c-4065-88f4-6f1e627ee7ea',
          'general',
          'FG-01 stopgap probe 2026-05-15',
          'open')
  RETURNING id
),
new_m AS (
  INSERT INTO ticket_messages (ticket_id, sender_type, body)
  SELECT id, 'staff', 'Hello — please ignore. FG-01 stopgap probe initiated by ops.'
  FROM new_t
  RETURNING id, ticket_id
)
SELECT (SELECT id FROM new_t) AS ticket_id, (SELECT id FROM new_m) AS message_id;
-- ticket_id  = 1ded4454-53c9-4ada-97be-3fbad89763e9
-- message_id = cab49fc5-11ed-4a06-9286-bc1c376c0391
```

Result:
- `trg_notify_ticket_reply` fired exactly once and inserted a `type='ticket'`
  notification for investor `6d8b2dfa-…`. The trigger does NOT special-case
  "is this the first message on the ticket" — it only suppresses when
  `sender_type='investor'`. So an ops-authored first message lights the bell.
- The Flutter app's `/support` list (after reload) showed the new ticket at
  the top with status `open` and the subject "FG-01 stopgap probe 2026-05-15".
- Tapping in: the staff message rendered on the left in the green bubble.
  The "Type your reply…" input was active (because status='open'), so the
  investor can reply normally and the existing `reply-ticket` path handles
  it from there.

The only cosmetic blemish: the bell-side title says "New reply on your
ticket" even though for the investor this is the first contact. That copy
is hard-coded in `notify_ticket_reply()` and is the same wording used for
genuine replies. Acceptable in the short term; nicer-to-have to special-case
"first message → 'New message from ARL'" later.

Tear-down (both probe tickets and their derived notifications were deleted
after the run):

```sql
DELETE FROM notifications
WHERE (metadata->>'ticket_id') IN ('5cc42e84-…','1ded4454-…');
DELETE FROM support_tickets
WHERE id IN ('5cc42e84-…','1ded4454-…');
-- ticket_messages cascades via FK
```

---

## 7. Ops recipes

These are copy-pasteable SQL fragments. All run from the Studio SQL editor
(or any `service_role`/`postgres`-priv'd session). Always replace the
bracketed values; never run blind.

### Recipe T-1 — Reply to an open ticket from ops

```sql
-- 1. Look up the ticket (sanity check)
SELECT id, investor_id, subject, status, created_at
FROM support_tickets
WHERE id = '<ticket_uuid>';

-- 2. Add your reply. sender_type='staff' is what fires the bell.
INSERT INTO ticket_messages (ticket_id, sender_type, body)
VALUES (
  '<ticket_uuid>',
  'staff',
  'Your reply text here. Keep it on one paragraph; the investor sees this verbatim.'
)
RETURNING id, created_at;

-- 3. Optional: flip the ticket to in_progress so the investor sees it's been picked up.
UPDATE support_tickets
SET status = 'in_progress'
WHERE id = '<ticket_uuid>' AND status = 'open';
```

The trigger inserts the notification automatically — no second statement
needed. Don't insert into `notifications` by hand for this case; you'll
just create duplicates.

### Recipe T-2 — Close out (resolve) a ticket

```sql
UPDATE support_tickets
SET status = 'resolved'
WHERE id = '<ticket_uuid>'
RETURNING id, status, updated_at;
```

This does NOT fire any trigger. The investor sees the new status only on
the next list-refresh / reload. The reply input on their detail screen
disappears and is replaced by "This ticket is closed".

If you want to leave the investor a parting message before closing, do
T-1 first, then T-2.

### Recipe T-3 — Re-open a resolved ticket

Yes, supported by the CHECK constraint. Just flip the status back:

```sql
UPDATE support_tickets
SET status = 'open'         -- or 'in_progress' if you're actively working it
WHERE id = '<ticket_uuid>'
  AND status = 'resolved'
RETURNING id, status;
```

The investor's reply input comes back. No trigger fires on this UPDATE.

### Recipe T-4 — All tickets for one investor

```sql
SELECT t.id,
       t.subject,
       t.category,
       t.status,
       t.created_at,
       t.updated_at,
       (SELECT count(*)
          FROM ticket_messages m
         WHERE m.ticket_id = t.id) AS msg_count
FROM support_tickets t
WHERE t.investor_id = '<investor_uuid>'
ORDER BY t.updated_at DESC;
```

If you only know the investor's email or ARL id:

```sql
SELECT t.id, t.subject, t.status, t.created_at
FROM support_tickets t
JOIN investors i ON i.id = t.investor_id
JOIN auth.users u ON u.id = i.id
WHERE u.email = '<email>'
   OR i.arl_id = '<ARL-NNNN>'
ORDER BY t.updated_at DESC;
```

### Recipe T-5 — Unresolved tickets aging past N days

```sql
SELECT t.id,
       i.name        AS investor,
       i.arl_id,
       t.category,
       t.subject,
       t.status,
       t.created_at,
       (now() - t.created_at) AS age
FROM support_tickets t
JOIN investors i ON i.id = t.investor_id
WHERE t.status IN ('open','in_progress')
  AND t.created_at < now() - interval '<N> days'
ORDER BY t.created_at ASC;
```

Use N=2 for the daily triage queue, N=7 for the "we owe somebody an apology"
list.

### Recipe T-6 — Initiate a ticket TO an investor (FG-01 stopgap)

Today there is no ops UI for "open a ticket addressed to investor X". This
is the SQL workaround. The trigger will fire and the investor will see it
in their `/support` list and get a bell notification, identical to a reply
on an investor-initiated ticket.

```sql
-- One-shot CTE: create the ticket and the first staff message together.
WITH new_t AS (
  INSERT INTO support_tickets (investor_id, category, subject, status)
  VALUES (
    '<investor_uuid>',
    'general',                       -- or 'payout' | 'documents' | 'bank_change' | 'exit_request'
    '<short subject investor will see>',
    'open'
  )
  RETURNING id
)
INSERT INTO ticket_messages (ticket_id, sender_type, body)
SELECT id,
       'staff',
       '<full body of the message — appears verbatim in the green staff bubble>'
FROM new_t
RETURNING ticket_id, id AS message_id;
```

What happens:
1. The ticket row appears in the investor's `/support` list (RLS allows
   read since `investor_id = auth.uid()`).
2. The `trg_notify_ticket_reply` trigger fires (because `sender_type='staff'`)
   and inserts a `notifications` row with title "New reply on your ticket"
   and body "New reply on ticket #<first 8 chars of ticket_id>." — note
   the wording is "reply" even though this is the FIRST message; that's
   a known cosmetic issue (see Defect D-4).
3. The investor can reply via the normal `/ticket/<id>` screen → `reply-ticket`
   Edge Function. That path doesn't care who started the thread.
4. The investor does NOT get a Resend email — the email channel only fires
   from inside the Edge Functions. If you also want to email them, use a
   normal Resend send or wait for the future "outbound ops compose" UI.

Verification one-liner (replace ids):
```sql
SELECT n.id AS notif_id, n.title, n.body, n.created_at,
       t.id AS ticket_id, t.subject, t.status
FROM notifications n
JOIN support_tickets t ON (n.metadata->>'ticket_id')::uuid = t.id
WHERE t.id = '<ticket_uuid_from_above>';
```

If you typo'd the investor_uuid the ticket simply lives orphaned — no
investor will ever see it. Validate the investor_uuid first with:
```sql
SELECT id, name, arl_id FROM investors WHERE id = '<investor_uuid>';
```

---

## 8. Defects + open questions

### Defects

**D-1 — Status changes don't propagate without a manual reload (P2)**

The Flutter `_ticketsProvider` and `ticketByIdProvider` are vanilla
`FutureProvider`s with no Supabase Realtime subscription and no
auto-`invalidate`. When ops flips a ticket to `in_progress` or `resolved`,
the investor sees the change only on the next `F5` or full route remount.
Tapping out of `/support` and back via `context.go(...)` does **not**
invalidate the future because GoRouter holds the keepalive.

Impact: ops-driven status flips look "lost" to the investor in real time.
Concrete reproduction is in §6, Test 3.

Possible fixes: subscribe to `support_tickets` realtime in
`_ticketsProvider`; OR wire a pull-to-refresh that calls
`ref.invalidate(_ticketsProvider)`; OR (cheapest) flip both providers to
`autoDispose` with a short `keepAlive` and document the limitation.

**D-2 — Submit button overlaps the bottom nav on short viewports (P2)**

In `new_ticket_screen.dart` the Submit button sits at y≈590, right above
the bottom nav bar at y≈800-ish. On the ~858px Chrome viewport the
spacing is comfortable, but on a small phone or a zoomed-in browser the
submit and the nav are close enough that a missed tap re-routes to whatever
nav target was nearer. In my Test 1 first attempt I tapped Submit and
landed on `/documents` because the click registered against the nav.
The actual POST went through, but visually the form looked like it ate
the submit silently.

Possible fixes: add bottom padding equal to `MediaQuery.viewPadding.bottom`
+ ~16; OR put the submit inside an `Hide on keyboard` SafeArea so the
bottom nav drops below it during input.

**D-3 — Ticket IDs in the My-Tickets list are full UUIDs (P3)**

The card's "id" line renders `raw['id']` directly, which is the full
36-char UUID. The mock fallback shows nice "TKT-2847" style IDs, so the
visual disparity is obvious. The HTML design prototype also uses the
short form.

Possible fixes: render `'#' || substr(id, 1, 8)` in the card. The full
UUID is still available via the `/ticket/<id>` URL and the detail screen
title.

**D-4 — Notification title is misleading for ops-initiated tickets (P3)**

`notify_ticket_reply()` always emits the title "New reply on your ticket"
and body "New reply on ticket #<short_id>." For a Recipe T-6 (ops
initiates), this is the first contact — calling it a "reply" is a small
white lie. Investors won't be confused for long, but it's wrong wording.

Possible fix: branch the title/body on `(SELECT count(*) FROM
ticket_messages WHERE ticket_id = NEW.ticket_id AND id <> NEW.id)`. If 0,
emit "New message from ARL". If >0, keep the current copy. Trivial
trigger edit, no API surface change. **Do not apply without explicit
greenlight** — copy changes ripple to investor expectations and want a
product call.

**D-5 — `bank_change` and `exit_request` ticket categories are not user-creatable from the UI (P3, by design)**

The category dropdown in `new_ticket_screen.dart` only exposes 5 labels
mapping to 3 enum values (`payout`, `documents`, `general`). The
`bank_change` and `exit_request` categories exist in the CHECK constraint
and are reachable only via SQL or from the dedicated bank-change / exit
flows. Worth knowing because ops will see these categories on tickets
that did NOT come from the support form.

### Open questions

**Q-1**: Should T-6 (ops-initiated ticket) also send an email to the
investor? Today only the Edge Functions send via Resend; manual SQL
inserts don't. If we want symmetry, we'd need either an `AFTER INSERT`
trigger that calls a webhook → Edge Function, or an explicit ops UI that
wraps T-6 in a function call. Worth a product decision before building.

**Q-2**: Are we OK with `D-1` long-term? Realtime would tighten the loop
for resolved-status-flips significantly. But it'd be the first place we
add a `subscribe(...)` in this codebase — worth checking with engineering
whether they want to set the precedent here or in `notifications` first.

**Q-3**: The 24h rate limit is 5 tickets. Is that still right for
50-500 investors? No one's hit it in production yet. Open to lowering to
3 if we want to nudge investors toward consolidating issues.

**Q-4**: There's no migration for an `auth.users.is_staff` flag and no
RPC for "ops authenticated reply". All staff replies go through Studio
today. Migration 006 (line 8) notes that explicitly:
"ARL staff respond via Supabase Studio". When we eventually build an ops
UI we'll want a proper auth boundary, not a service_role key bundled in
the client. Filing for visibility.

---

## 9. Migration references

| Migration                                                           | What it does                                                       |
|---------------------------------------------------------------------|--------------------------------------------------------------------|
| `20260411074932_006_notifications_support_bank.sql`                 | Creates `notifications`, `support_tickets`, `ticket_messages`, `bank_change_requests`. Adds indexes `idx_tickets_investor_status`, `idx_ticket_messages_ticket`. |
| `20260411075029_009_row_level_security.sql`                         | Enables RLS on all newly created tables.                            |
| `20260411075041_010_updated_at_triggers.sql`                        | Generic `updated_at = now()` trigger on UPDATE for relevant tables. |
| `20260411075138_012_performance_fixes.sql`                          | Index tuning (added `idx_support_tickets_project_id`).              |
| `20260427150200_017_drop_edge_only_insert_policies.sql`             | Drops investor-facing INSERT/UPDATE policies on `support_tickets` and `ticket_messages`. Writes must now go through `create-ticket` / `reply-ticket` edge functions. |
| `20260427150300_018_policies_to_authenticated_role.sql`             | Rebinds remaining SELECT policies to the `authenticated` role.      |
| `20260513040000_034_notification_triggers.sql`                      | Defines `notify_ticket_reply()` + `trg_notify_ticket_reply`, plus three sibling triggers for KYC / exit / bank-change.   |

Rollback for migration 034 is in `docs/ops_admin_guide.md` Part 9 at
the bottom. Removing the trigger is reversible; removing the tables is
not (cascades into FKs). Don't.

---

End of doc. If you ran a recipe and the investor didn't see anything,
re-run §6 Test 3's `F5` step — that's almost always the cause. If it's
not, ping engineering with the ticket id and the SQL you ran.
