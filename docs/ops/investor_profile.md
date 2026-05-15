# Editing an Investor's Profile — Ops Runbook

**Audience.** ARL ops engineers (you, day-to-day) who need to change something
about a live investor — KYC, address, allocations, payouts, bank, PIN, the
auth row, anything. You are not expected to be a Flutter or Postgres expert.
You are expected to know what Supabase Studio is, how to paste SQL into the
SQL Editor, and how to log in to Zoho CRM.

**Scope.** Every editable field, status, request type and auth-level control
for the `investors` table and everything that fans out from it.

**Project.** Supabase project ID `oynfhdqizebvgmaoiuax`. Test investor:
`ofclash98@gmail.com`, investor id `27d3735e-470d-47a5-a413-9ae502194d3d`.

---

## 1. Mental model — read this first

The investor portal has two databases. Zoho CRM is the **master**. Supabase
is the **slave**. The plumbing between them is one Edge Function:
`supabase/functions/zoho-crm-webhook/index.ts`. It fires whenever a Zoho
workflow on `Contacts`, `LLP_Creation_Module` or `LLP_UnitAllocation_Module`
hits the public endpoint.

The webhook is destructive. It does an UPSERT keyed on `zoho_contact_id` /
`zoho_llp_id` / `zoho_allocation_id`. **Every Zoho-mirrored column in
Supabase is overwritten on the next webhook delivery.** If you reach into
Supabase Studio and `UPDATE investors SET phone = '...'`, your change
survives until the next time someone edits that contact in Zoho — then your
edit is gone with no warning.

This drives the cardinal rule:

> If a column came from Zoho, edit it in Zoho. If a column is Supabase-native
> (KYC trigger status on a request, soft-delete timestamps, app PIN, ticket
> status), edit it in Supabase.

### Columns the webhook clobbers — DO NOT edit in Supabase

`investors`: `name`, `email`, `phone`, `salutation`, `kyc_status` (yes — the
webhook re-maps `Contacts.KYC` → `kyc_status` on every Contact write),
`pan_masked`, `bank_account_masked`, `bank_ifsc`, `bank_branch`,
`bank_holder_name`, `bank_name`, `address_line1`, `city`, `state`,
`pincode`, `country`, `unit_allocated`, `payment_received`,
`profile_verified`, `agreement_signed`, `fema_applicable`, `updated_at`,
`last_synced_at`.

`investor_units`: every business column — see `handleAllocation` in
`zoho-crm-webhook/index.ts`. The only safe Supabase-side edits are
`deleted_at` (soft cancel) and post-soft-delete recovery.

`payouts`: rows with `source='crm'` are re-upserted by `idempotency_key`
(`<zoho_allocation_id>_payout_<n>`). Edits to those rows are clobbered.
Rows with `source='manual'` are yours to edit forever.

`projects` / `llps`: same story. Anything mirroring `LLP_Creation_Module` is
overwritten. Supabase-native columns (`cover_image_path`, `color_hex`,
`accent_hex`, `marketplace_sort_order`, `latitude`, `longitude`,
`approx_radius_meters`, `tagline`, `marketplace_image`) are safe to edit in
Studio.

### Columns the webhook does NOT touch — Supabase is authoritative

- `investors.arl_id` — created at onboard or assigned by ops after a
  self-onboard.
- `investors.date_of_birth` — only written by the Flutter initial-setup
  flow. **The webhook ignores `Contacts.Date_of_Birth` entirely** (defect
  P2 — see §11).
- `investors.aadhaar_masked` — only written by Flutter onboarding. **The
  webhook ignores `Contacts.Aadhaar_Number`** (defect P2 — see §11).
- `investors.deleted_at` — set by Zoho contact-delete fan-out OR by ops
  (see §10).
- All the request tables: `bank_change_requests`, `exit_requests`,
  `kyc_resubmissions`, `support_tickets`, `ticket_messages`,
  `consultation_requests`, `notifications`, `user_settings`,
  `login_events`. None of these get touched by any sync.

### Notification triggers — migration 034

Four DB triggers turn ops status changes into in-app notification rows:

| Trigger | Table | Fires on |
|---|---|---|
| `trg_notify_investor_kyc_status_change` | `investors` | `kyc_status` pending → verified \| rejected |
| `trg_notify_exit_request_status_change` | `exit_requests` | `status` pending → approved \| rejected \| settled |
| `trg_notify_ticket_reply` | `ticket_messages` | INSERT where `sender_type != 'investor'` |
| `trg_notify_bank_change_status_change` | `bank_change_requests` | `status` pending → approved \| rejected |

**Gotcha.** All four are gated `OLD.status = 'pending'`. If a row is
already in `approved` and you flip to `settled`, **no notification fires**.
This is verified — see §4 live tests.

---

## 2. Personal info

### 2.1 Name (`investors.name`)

- WHAT — `investors.name TEXT NOT NULL`. There is no `first_name` /
  `last_name` / `full_name` / `mailing_address` column on `investors`.
  The webhook builds `name` from `Contacts.First_Name + Contacts.Last_Name`.
- WHO — Zoho operator.
- WHERE — Zoho CRM → Contacts → the contact → edit First Name / Last Name.
- WHEN — Whenever the Zoho workflow fires the webhook (usually < 60 s).
- NOTIFICATION — None.
- SQL recipe — **do not write directly**. If urgent and Zoho is down:
  ```sql
  -- Emergency only; next webhook will overwrite.
  UPDATE public.investors
     SET name = 'New Full Name'
   WHERE id = '<investor_id>';
  ```
- ROLLBACK — Edit the field back in Zoho.

### 2.2 Phone (`investors.phone`)

- WHAT — `investors.phone TEXT`. Webhook source: `Contacts.Mobile` if
  present, else `Contacts.Phone`.
- WHO — Zoho operator.
- WHERE — Zoho CRM → Contacts → Mobile.
- WHEN — Webhook fires < 60 s.
- NOTIFICATION — None.
- SQL recipe — none; edit in Zoho.
- ROLLBACK — Revert in Zoho.

### 2.3 Email (TWO places — keep both in mind)

- WHAT — `investors.email` (the app reads this in the profile screen) AND
  `auth.users.email` (the sign-in identity, the password-reset target, what
  the Studio shows on the Auth Users page).
- WHO — Both Zoho operator and Studio ops, depending.
- WHERE — Two surfaces:
  - **`investors.email`** is updated by the webhook from `Contacts.Email`.
    Editing in Zoho propagates here.
  - **`auth.users.email`** is **never touched by the webhook** (verified —
    `zoho-crm-webhook/index.ts` writes only to `public.investors`). To
    change the sign-in email, Studio ops must do it explicitly via
    Auth → Users → click investor → Edit email.
- WHEN — Zoho side: < 60 s. Auth side: instant.
- NOTIFICATION — None automatic. Supabase will send a confirmation to the
  new email if "Confirm email change" is on for the project.
- SQL recipe (Auth side, if you cannot use Studio):
  ```sql
  -- Service-role only. Cannot be run via PostgREST.
  -- Prefer the Auth Users UI; this is the SQL fallback.
  UPDATE auth.users
     SET email = 'new@example.com',
         email_change = NULL,
         email_change_token_new = NULL
   WHERE id = '<investor_id>';
  -- Also clear the cached email on the investors row so the profile
  -- screen matches before the next Zoho sync.
  UPDATE public.investors
     SET email = 'new@example.com'
   WHERE id = '<investor_id>';
  ```
- ROLLBACK — Re-run with the previous email. Note that if you only fix
  one side, the two will drift; always update both.

**Open question — see §11 — should the webhook also push email changes to
`auth.users` so the two stay in lockstep? Today they can diverge silently.**

### 2.4 Mailing address (street / city / state / zip / country)

- WHAT — `investors.address_line1`, `address_line2` (column exists, never
  written by the webhook), `city`, `state`, `pincode`, `country`. Source:
  `Contacts.Mailing_Street` / `Mailing_City` / `Mailing_State` /
  `Mailing_Zip` / `Mailing_Country`.
- WHO — Zoho operator.
- WHERE — Zoho CRM → Contacts → Mailing Address section.
- WHEN — Webhook < 60 s.
- NOTIFICATION — None.
- SQL recipe — none; edit in Zoho.
- ROLLBACK — Revert in Zoho.

**Defect P3.** `investors.address_line2` exists in the schema (migration
002) but the webhook never writes it — no corresponding Zoho field is
mapped. Either map `Contacts.Mailing_Street_2` (if Zoho exposes one) or
drop the column.

### 2.5 Salutation (`investors.salutation`)

- WHO — Zoho operator. Source: `Contacts.Salutation`.
- Same shape as the others above.

---

## 3. KYC

### 3.1 `kyc_status` enum

- WHAT — `investors.kyc_status TEXT NOT NULL DEFAULT 'pending'` with
  CHECK constraint `kyc_status IN ('pending','in_progress','verified','rejected')`.
- WHO — Zoho operator (preferred). Studio ops only in emergencies.
- WHERE — Zoho CRM → Contact → KYC picklist. Acceptable Zoho values that
  map cleanly: `Pending`, `In Progress` (→ `in_progress`), `Completed` or
  `Verified` (→ `verified`), `Rejected`, `Not Started` (→ `pending`).
  Anything unrecognised silently maps to `pending` (see `mapKycStatus` in
  `zoho-crm-webhook/index.ts`).
- WHEN — Webhook < 60 s.
- NOTIFICATION — Yes. `trg_notify_investor_kyc_status_change` fires on
  `OLD.kyc_status='pending'` AND `NEW.kyc_status IN ('verified','rejected')`.
  Notification body for verified: `"Your KYC has been verified. Tap to view."`
  For rejected: `"Your KYC has been rejected. Please re-submit."`
  See §4 live test #1 — verified.
- SQL recipe (emergency, when Zoho is unreachable):
  ```sql
  UPDATE public.investors
     SET kyc_status = 'verified'   -- or 'rejected'
   WHERE id = '<investor_id>';
  ```
- ROLLBACK — Flip the status back. **WARNING**: the trigger only fires
  pending → (verified|rejected). It does NOT fire verified → pending. So a
  rollback doesn't generate a duplicate notification — but a subsequent
  pending → verified WILL. If you're cleaning a test, delete the
  notification row too:
  ```sql
  UPDATE public.investors SET kyc_status = 'pending' WHERE id = '<id>';
  DELETE FROM public.notifications
   WHERE investor_id = '<id>' AND type = 'kyc'
   ORDER BY created_at DESC LIMIT 1;
  ```

### 3.2 KYC re-submissions

When an investor's KYC was rejected and they re-uploaded via the in-app
KYC screen, a row lands in `kyc_resubmissions` (migration 028). Status
enum: `pending | in_review | accepted | rejected`. There is **no trigger
or notification** wired up for this table — see §11. Ops re-verifies the
docs at `pan_doc_url` / `aadhaar_doc_url`, then either:

```sql
-- Accept the re-submission and bump the investor's KYC back to verified.
UPDATE public.kyc_resubmissions
   SET status = 'accepted'
 WHERE id = '<resubmission_id>';

UPDATE public.investors
   SET kyc_status = 'verified'
 WHERE id = '<investor_id>';   -- fires the notification
```

The investor sees the KYC notification but not a kyc_resubmissions-specific
one. Acceptable for now.

---

## 4. Sensitive identity fields

### 4.1 What is stored

All raw PAN / Aadhaar / bank-account numbers are **masked at the application
layer in the webhook** before they hit the database (`maskPan` /
`maskBankAccount` in `zoho-crm-webhook/index.ts`). The DB columns are
literally named `pan_masked`, `bank_account_masked`, `aadhaar_masked`.

| Column | Source | Masked form |
|---|---|---|
| `pan_masked` | Zoho `Contacts.PAN_Number` via `maskPan` | `RTYUI****L` (first 5 + last 1) |
| `bank_account_masked` | Zoho `Contacts.Bank_Account_Number` via `maskBankAccount` | `XXXX-XXXX-9012` (last 4) |
| `aadhaar_masked` | **Not webhook-sourced** — client only via initial-setup flow | `XXXX-XXXX-1234` (last 4) |
| `date_of_birth` | **Not webhook-sourced** — client only | ISO date |

Note: there is NO `pan_number` / `aadhaar_number` column. The webhook
ingests the raw values, masks them in-memory, writes the masked form to
`investors`, **and** masks them again in `sanitizeForLogging` before
writing the audit row to `webhook_log.payload` so the 90-day audit log
never retains raw PII.

Bank metadata (`bank_ifsc`, `bank_branch`, `bank_name`, `bank_holder_name`)
is stored plaintext — these are not secrets.

### 4.2 Where the masking happens

- DB column: not a view, not RLS, not a trigger — masked-in-place at
  webhook write time.
- Reads: there is no unmask. The raw values do not exist in Supabase.
- The investor profile screen reads the masked columns directly.

### 4.3 Editing

- WHO — Zoho operator (PAN, bank account, bank metadata). The investor
  themselves for Aadhaar and DOB at first signup (initial setup wizard).
- WHERE — Zoho CRM → Contact → PAN Number / Bank Account Number / Bank
  Name / IFSC / Branch / Account Holder Full name. Aadhaar and DOB are
  NOT in Zoho today.
- WHEN — Webhook < 60 s.
- NOTIFICATION — None for PAN / bank. None for DOB / Aadhaar
  (those don't change after onboarding in practice).
- SQL recipe — **DO NOT** `UPDATE investors SET pan_masked = ...`. The
  next Zoho webhook overwrites with whatever's there. The only legitimate
  Supabase-side write to these columns is the one-time onboarding upsert
  by the investor themselves.
- ROLLBACK — Edit Zoho back.

### 4.4 If an investor wants to change their PAN / bank

PAN: rare, requires re-KYC. Update in Zoho; flip `kyc_status` to
`in_progress` then back to `verified` once re-verified.

Bank: investor submits a `bank_change_requests` row from the app (§7), ops
approves, ops manually updates Zoho's `Contacts.Bank_*` fields, webhook
syncs back the masked form, ops flips the request to `approved`.

---

## 5. Project assignments / allocations (`investor_units`)

### 5.1 Where rows come from

Zoho CRM `LLP_UnitAllocation_Module`. Each allocation record there →
one `investor_units` row here, keyed by `zoho_allocation_id` (unique).
The fan-out also unpacks `UTR_1..10` / `Amount_1..10` / `Date_1..10`
into rows in `payouts` (see §6).

Resolution chain (`handleAllocation` in the webhook):

1. Looks up `investors.id` by `zoho_contact_id` = `data.Customer.id`.
2. Looks up `llps.id` by `zoho_llp_id` = `data.LLP.id`.
3. Picks the default `projects` row under that LLP (`order by updated_at asc limit 1`).
4. UPSERTs `investor_units` on `zoho_allocation_id`.

If step 1 fails (investor not yet onboarded) the webhook throws
`investor not found for zoho_contact_id <id>` and `webhook_log.status`
goes `failed`. Onboard the investor first.

### 5.2 Recipes

**Create a new allocation.**

- WHO — Zoho operator.
- WHERE — Zoho CRM → `LLP_UnitAllocation_Module` → New record. Pick
  Customer (the Contact), LLP (the project), fill Issued_Units /
  Unit_Price / Capital_Invested / Investment_Date / etc.
- WHEN — Webhook < 60 s.
- NOTIFICATION — `payout` notification is created if any UTR_1..10 fields
  are populated at creation time (see §6). No notification for the
  allocation itself.

**Re-allocate (edit units, price, capital).**

- WHO — Zoho operator.
- WHERE — Same record in Zoho. Edit any field. The webhook upserts
  by `zoho_allocation_id` so updates are clean.
- WHEN — < 60 s.

**Cancel an allocation (soft-delete).**

- WHO — Studio ops. The Zoho webhook does NOT fan out delete for
  `LLP_UnitAllocation_Module` — only `Contacts` and `LLP_Creation_Module`
  are wired in (`handleContactDelete` / `handleLLPDelete`). So if Zoho
  cancels an allocation, ops must mirror it manually.
- WHERE — Supabase Studio SQL editor.
- WHEN — Immediate.
- NOTIFICATION — None automatic. Manually create one if the investor
  needs to know.
- SQL recipe:
  ```sql
  -- Soft-cancel an allocation. RLS hides deleted rows from the
  -- investor (migration 042); FK to payouts / exit_requests stays.
  UPDATE public.investor_units
     SET deleted_at = NOW()
   WHERE id = '<allocation_id>';
  ```
- ROLLBACK:
  ```sql
  UPDATE public.investor_units
     SET deleted_at = NULL
   WHERE id = '<allocation_id>';
  ```

**Hard-delete an allocation (test data only).**

```sql
-- Will cascade-NULL payouts.allocation_id, cascade-delete exit_requests.
-- DO NOT use on production allocations — you lose the FK trail.
DELETE FROM public.investor_units WHERE id = '<id>';
```

---

## 6. Payouts (`payouts`)

### 6.1 Where rows come from

Three sources distinguished by `source` column:

- `source='crm'` — unpacked from `LLP_UnitAllocation_Module.UTR_<n>` /
  `Amount_<n>` / `Date_<n>` by the webhook. Idempotency key:
  `<zoho_allocation_id>_payout_<n>`. Status is forced to `processed` at
  insert.
- `source='books'` — reserved for a future `zoho-books-webhook`. Not used yet.
- `source='manual'` — ops INSERTs in Studio.

`status` enum: `pending | processed | on_hold` (CHECK constraint).
`is_demo` boolean flag distinguishes seeded test rows.

### 6.2 Recipes

**Add a payout manually.**

- WHO — Studio ops.
- WHERE — SQL editor.
- WHEN — Immediate.
- NOTIFICATION — No auto-trigger for manual inserts. The CRM-source
  webhook creates a single `payout` notification per webhook batch (see
  `handleAllocation`), but that fires only from the webhook path. If you
  want to notify, INSERT into `notifications` manually:
- SQL recipe:
  ```sql
  -- Manual payout. Pin investor + project + allocation, supply UTR + amount.
  INSERT INTO public.payouts (
    investor_id, project_id, allocation_id,
    source, amount, payout_date, utr, status, notes
  ) VALUES (
    '<investor_id>',
    '<project_id>',
    '<allocation_id>',          -- nullable, FK to investor_units
    'manual',
    50000.00,
    '2026-05-15',
    'UTR1234567890',
    'processed',
    'Ad-hoc payout — see ops ticket #...'
  );

  -- Optional: notify the investor.
  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  VALUES (
    '<investor_id>', 'payout',
    'Payout processed',
    'Your payout for <project name> has been processed.',
    jsonb_build_object('amount', 50000.00, 'utr', 'UTR1234567890')
  );
  ```
- ROLLBACK:
  ```sql
  DELETE FROM public.payouts WHERE id = '<payout_id>';
  DELETE FROM public.notifications WHERE id = '<notification_id>';
  ```

**Change a payout's status (e.g. on-hold a fraudulent payout).**

```sql
UPDATE public.payouts SET status = 'on_hold' WHERE id = '<payout_id>';
```

Note: there is no trigger for status changes on `payouts`. The investor
will not be notified.

### 6.3 "Next Payout" surfacing on Home

Home reads from the `portfolio_summary` view (migration 008). The "Next
Payout" date there is:

```sql
MIN(p.payout_date) FILTER (WHERE p.status = 'pending')
```

So a payout shows up as "next" when it has `status='pending'` and a
`payout_date` >= today. It is **not** driven by `investor_units.next_payout_date`
(that column exists from Zoho's `Next_Payout` field but the Home tile
ignores it; only the Projects screen surfaces it).

To make a payout appear as the next one for an investor:

```sql
INSERT INTO public.payouts (
  investor_id, project_id, source, amount, payout_date, status
) VALUES (
  '<id>', '<project>', 'manual', 25000.00, '2026-06-15', 'pending'
);
```

To make it disappear: change status to `processed` or `on_hold`, or
delete the row.

---

## 7. Exit requests (`exit_requests`)

### 7.1 Schema and flow

Migration 029 — investor taps "Request Exit" on the ExitScreen → row
inserted with `status='pending'`. Migration 044 adds an RLS WITH CHECK
that the allocation's `investment_date + 5 years <= NOW()` (the 5-year
lock-in), enforced server-side on INSERT only.

Status enum: `pending | approved | rejected | settled`.

### 7.2 Lock-in workaround for testing

The lock-in policy is on the **authenticated INSERT** path. Service-role
inserts (Studio SQL editor, Edge Functions running as service_role)
bypass RLS entirely. So for testing, ops can insert a `pending`
exit_request for any allocation regardless of investment_date.

Confirmed in §8 live test #2: inserted a dummy exit_request for the
test investor whose `investment_date` is 2026-05-13 (two days ago) via
Studio SQL — it succeeded.

### 7.3 Recipes

**Approve.**

- WHO — Studio ops.
- WHEN — Immediate.
- NOTIFICATION — Yes, `trg_notify_exit_request_status_change` fires.
  Title: `"Exit request approved"`. Body: `"Your exit request has been
  approved. Settlement will follow."`
- SQL:
  ```sql
  UPDATE public.exit_requests
     SET status = 'approved', resolved_at = NOW()
   WHERE id = '<exit_request_id>';
  ```

**Reject.**

- NOTIFICATION — Title `"Exit request rejected"`, body `"Your exit
  request has been rejected. Reach out to support for details."`
- SQL:
  ```sql
  UPDATE public.exit_requests
     SET status = 'rejected', resolved_at = NOW()
   WHERE id = '<id>';
  ```

**Settle.**

- WARNING — The notification trigger only fires on `pending → settled`,
  NOT on `approved → settled`. So if you went pending → approved → settled
  (the natural workflow), **the investor gets the "approved" notification
  but never a "settled" notification**. This is a defect — see §11.
- SQL (direct pending → settled, generates notification):
  ```sql
  UPDATE public.exit_requests
     SET status = 'settled', resolved_at = NOW()
   WHERE id = '<id>' AND status = 'pending';
  ```
- SQL (approved → settled, no notification — current real-world path):
  ```sql
  UPDATE public.exit_requests SET status = 'settled', resolved_at = NOW()
   WHERE id = '<id>';
  -- Manually insert the missing notification:
  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT user_id, 'exit', 'Exit settled',
         'Your exit settlement has been processed.',
         jsonb_build_object('exit_request_id', id, 'status', 'settled')
    FROM public.exit_requests WHERE id = '<id>';
  ```

**Rollback any status change.**

```sql
UPDATE public.exit_requests SET status = 'pending', resolved_at = NULL
 WHERE id = '<id>';
DELETE FROM public.notifications
 WHERE metadata->>'exit_request_id' = '<id>'
   AND created_at > NOW() - INTERVAL '1 hour';
```

---

## 8. Bank change requests (`bank_change_requests`)

### 8.1 Flow

Investor submits via the `bank-change-request` Edge Function (which
enforces a 7-day cooldown + masked-input check). Row lands with
`status='pending'`. Migration 043 added the `updated_at` column the
trigger needs.

### 8.2 Recipe — process a request

1. Phone-verify with the investor (out of band).
2. Edit the bank fields in **Zoho** Contact (`Bank_Name`,
   `Bank_Account_Number`, `ISFC_Code`, `Bank_Branch`,
   `Account_Holder_Full_name`). The webhook syncs the masked form into
   `investors`.
3. Flip the request row to approved (or rejected).

- WHO — Zoho operator for the bank field push; Studio ops for the
  request status flip.
- WHEN — Steps 1–2 manual. Step 3 immediate + notification.
- NOTIFICATION — Yes. `trg_notify_bank_change_status_change`. Body for
  approved: `"Your bank account update has been approved and will reflect
  after the next CRM sync."` For rejected: `"Your bank account update was
  rejected. <NEW.notes>"` (if `notes` is set).
- SQL recipe:
  ```sql
  -- Approve
  UPDATE public.bank_change_requests
     SET status = 'approved', resolved_at = NOW(),
         notes  = 'Verified by phone with investor on YYYY-MM-DD.'
   WHERE id = '<request_id>';

  -- Reject
  UPDATE public.bank_change_requests
     SET status = 'rejected', resolved_at = NOW(),
         notes  = 'Phone verification failed — number unreachable.'
   WHERE id = '<request_id>';
  ```
- ROLLBACK:
  ```sql
  UPDATE public.bank_change_requests
     SET status = 'pending', resolved_at = NULL
   WHERE id = '<id>';
  DELETE FROM public.notifications
   WHERE metadata->>'bank_change_request_id' = '<id>';
  ```

### 8.3 Gotcha — bank columns are masked

You cannot read the existing bank account number from Supabase — only
`bank_account_masked` = `XXXX-XXXX-9012`. To verify which account the
investor was on, look in Zoho. The Supabase row is the masked summary.

---

## 9. Auth-level controls

The Supabase Auth layer is its own surface — separate from `public.investors`.

### 9.1 Unban a banned auth user

Migration 030 + the webhook's `handleContactDelete` ban the auth.users
row using `ban_duration: "876000h"` (100 years). To re-enable:

- WHO — Studio ops.
- WHERE — Two options:
  - **Studio UI**: Auth → Users → click the investor → "Remove ban" button.
  - **SQL** (less convenient but scriptable):
    ```sql
    UPDATE auth.users
       SET banned_until = NULL
     WHERE id = '<investor_id>';
    ```
- WHEN — Immediate. Any cached refresh token can now exchange again.
- NOTIFICATION — None.
- ROLLBACK:
  ```sql
  UPDATE auth.users
     SET banned_until = (NOW() + INTERVAL '100 years')
   WHERE id = '<investor_id>';
  ```

### 9.2 Manually invalidate all sessions for an investor

Useful if you suspect a stolen device.

- SQL recipe:
  ```sql
  -- Kills every refresh token. Next API call returns 401; user must re-auth.
  DELETE FROM auth.refresh_tokens WHERE user_id = '<investor_id>';
  -- Optional: also nuke any sessions row.
  DELETE FROM auth.sessions WHERE user_id = '<investor_id>';
  ```
- NOTIFICATION — None.
- ROLLBACK — Cannot un-delete a refresh token. The user re-signs in.

### 9.3 Send a password recovery email

- WHO — Studio ops.
- WHERE — Studio Dashboard → Auth → Users → click the investor → "Send
  recovery" button. This emits a magic-link email.
- WHEN — Email sent immediately. Link is single-use, 1-hour expiry by
  default.
- NOTIFICATION — Email only. No in-app notification.
- ROLLBACK — Cannot revoke the sent email. If the user shouldn't have
  received it, also kill their sessions (§9.2) so any token that link
  produces is moot.

---

## 10. PIN reset

### 10.1 Where the PIN lives

`public.user_settings.app_pin_hash` / `app_pin_salt` / `app_pin_iterations`
(migration 026). Hashing is done **client-side** in
`lib/core/repositories/user_settings_repository.dart` — PBKDF2-style
100 000 iterations of SHA-256 with a per-user 16-byte salt. The DB
never sees the plaintext PIN.

### 10.2 Reset

- WHO — Studio ops, after identifying the investor (typically through a
  support ticket).
- WHERE — SQL editor.
- WHEN — Immediate. User is prompted to set a new PIN on next sign-in.
- NOTIFICATION — None.
- SQL recipe:
  ```sql
  -- Nukes the PIN. user_settings row still exists for biometric +
  -- notifications toggles; only the three PIN columns are cleared.
  UPDATE public.user_settings
     SET app_pin_hash = NULL,
         app_pin_salt = NULL,
         app_pin_iterations = NULL
   WHERE user_id = '<investor_id>';

  -- If they have no user_settings row at all (never opened SecurityScreen),
  -- this returns 0 rows updated — which is fine; the SecurityScreen will
  -- create one when they re-set the PIN.
  ```
- ROLLBACK — There is no rollback; you cannot recover the previous PIN
  (it was a hash). The user just re-sets.

### 10.3 Disabling the PIN entirely

Same SQL as above. The SecurityScreen ("Remove PIN" tile) does this for
the user themselves via `UserSettingsRepository.clearPin()`.

---

## 11. Account deletion

### 11.1 Soft-delete (recommended for retiring an investor)

Two-step. Mark the row soft-deleted and ban the auth row so refresh
tokens stop working.

- WHO — Studio ops.
- WHERE — SQL editor.
- WHEN — Immediate. RLS (migration 031) hides the row from any
  `select * from investors` the investor's session would issue; the
  Flutter repository layer also filters `deleted_at IS NULL` defensively.
- NOTIFICATION — None.
- SQL recipe:
  ```sql
  -- Step 1: soft-delete the investors row.
  UPDATE public.investors
     SET deleted_at = NOW()
   WHERE id = '<investor_id>';

  -- Step 2: ban the auth user so any refresh token is invalidated.
  -- Service-role only; cannot be done via PostgREST.
  UPDATE auth.users
     SET banned_until = (NOW() + INTERVAL '100 years')
   WHERE id = '<investor_id>';
  ```
- ROLLBACK:
  ```sql
  UPDATE public.investors SET deleted_at = NULL WHERE id = '<id>';
  UPDATE auth.users SET banned_until = NULL WHERE id = '<id>';
  ```

### 11.2 Hard-delete (test investors only)

DANGER. This cascade-deletes everything: investor_units → payouts (via
`ON DELETE CASCADE`), documents, notifications, support_tickets,
ticket_messages, bank_change_requests, exit_requests, user_settings,
login_events, kyc_resubmissions, consultation_requests. The audit trail
is gone. Also wipes the auth.users row (ON DELETE CASCADE from
`investors.id → auth.users.id`).

Use only on test accounts where audit doesn't matter.

```sql
-- Last warning. There is no rollback.
-- Confirm the investor is a test fixture first:
SELECT id, email, arl_id, name FROM public.investors WHERE id = '<id>';

-- Hard-delete:
DELETE FROM public.investors WHERE id = '<id>';
-- auth.users.id cascade-deletes via FK.
```

For the test investor `27d3735e-470d-47a5-a413-9ae502194d3d` specifically:
**do not delete** — other investigations are still using it.

---

## 12. Live test results

Run on 2026-05-15 against project `oynfhdqizebvgmaoiuax`, investor
`27d3735e-470d-47a5-a413-9ae502194d3d`. All cleanups verified.

### Test 1 — KYC flip

```sql
UPDATE investors SET kyc_status='verified' WHERE id='27d3735e-470d-47a5-a413-9ae502194d3d';
```

Result: notification row created.

```
id:       2f520d88-925f-4b9a-9c74-595a131a1347
type:     kyc
title:    KYC verified
body:     Your KYC has been verified. Tap to view.
metadata: {"kyc_status":"verified","previous_status":"pending"}
```

Cleanup:

```sql
UPDATE investors SET kyc_status='pending' WHERE id='27d3735e-470d-47a5-a413-9ae502194d3d';
DELETE FROM notifications WHERE id='2f520d88-925f-4b9a-9c74-595a131a1347';
```

PASS.

### Test 2 — exit_request flip

Investor's `investment_date` (2026-05-13) does not satisfy the 5-year
lock-in. Service-role insert bypasses the RLS policy — confirmed working.

```sql
INSERT INTO exit_requests (investor_unit_id, user_id, reason, status)
VALUES ('5ecd6b08-bca7-4f25-9209-890235ac25e7',
        '27d3735e-470d-47a5-a413-9ae502194d3d',
        'OPS AUDIT TEST DUMMY', 'pending');
-- → id = 7c782ae3-5483-426e-9d8b-d81ae90e1098

UPDATE exit_requests SET status='approved', resolved_at=now()
 WHERE id='7c782ae3-5483-426e-9d8b-d81ae90e1098';
```

Notification:

```
id:       1640d87b-cd6b-416a-a272-2f01a8e06cfb
type:     exit
title:    Exit request approved
body:     Your exit request has been approved. Settlement will follow.
metadata: {"status":"approved", "exit_request_id":"...", "investor_unit_id":"..."}
```

Then flipped `approved → settled`:

```sql
UPDATE exit_requests SET status='settled' WHERE id='7c782ae3-5483-426e-9d8b-d81ae90e1098';
```

Resulting `count(*) where type='exit' AND last 5 min` = **1** (no new
notification fired). **Confirmed defect**: the trigger gates on
`OLD.status='pending'`, so `approved → settled` is silent.

Cleanup:

```sql
DELETE FROM exit_requests WHERE id='7c782ae3-5483-426e-9d8b-d81ae90e1098';
DELETE FROM notifications WHERE id='1640d87b-cd6b-416a-a272-2f01a8e06cfb';
```

PASS (notification works); DEFECT (settled-after-approved silent).

### Test 3 — bank_change_request flip

```sql
INSERT INTO bank_change_requests (
  investor_id, new_bank_name, new_account_masked, new_ifsc,
  new_holder_name, status, notes
) VALUES (
  '27d3735e-470d-47a5-a413-9ae502194d3d',
  'OPS-AUDIT-TEST-BANK', 'XXXX-XXXX-0000', 'TEST0000000',
  'Test Investor One-demo', 'pending', 'OPS AUDIT TEST DUMMY'
);
-- → id = 82619456-c415-4d55-a4fe-5f7dab537aba

UPDATE bank_change_requests SET status='approved', resolved_at=now()
 WHERE id='82619456-c415-4d55-a4fe-5f7dab537aba';
```

Notification:

```
type:     bank_change
title:    Bank change approved
body:     Your bank account update has been approved and will reflect after the next CRM sync.
metadata: {"status":"approved","bank_change_request_id":"82619456-..."}
```

`updated_at` was set on the bank_change_requests row by the
`set_updated_at` trigger — confirms migration 043 is live.

Cleanup:

```sql
DELETE FROM bank_change_requests WHERE id='82619456-c415-4d55-a4fe-5f7dab537aba';
DELETE FROM notifications WHERE id='5c2dad61-e3c9-49a5-b0d3-66e3358a209b';
```

PASS.

### Test 4 — final state verification

```sql
SELECT u.id, u.email AS auth_email, u.banned_until,
       i.email AS investors_email, i.kyc_status, i.deleted_at
  FROM auth.users u LEFT JOIN investors i ON i.id = u.id
 WHERE u.id='27d3735e-470d-47a5-a413-9ae502194d3d';
```

Output: `auth_email = investors_email = ofclash98@gmail.com`,
`banned_until = NULL`, `kyc_status = pending`, `deleted_at = NULL`.

Test investor is back to baseline. No artifacts remain.

---

## 13. Quick-reference

| Action | Where | Risk | SQL fragment / surface |
|---|---|---|---|
| Change name | Zoho | Low | Edit `Contacts.First_Name` / `Last_Name` |
| Change phone | Zoho | Low | Edit `Contacts.Mobile` |
| Change `investors.email` | Zoho | Low | Edit `Contacts.Email` |
| Change `auth.users.email` | Studio Auth UI | Med — drifts from `investors.email` if Zoho not updated too | UI button |
| Change address | Zoho | Low | Mailing Address fields |
| Flip KYC | Zoho preferred; SQL emergency | Low | `UPDATE investors SET kyc_status='verified' WHERE id=...` |
| Update PAN / bank fields | Zoho only | High if SQL — clobbered next webhook | Zoho `Contacts` |
| Create allocation | Zoho | Low | `LLP_UnitAllocation_Module` new record |
| Edit allocation | Zoho | Low | same record |
| Cancel allocation | Studio SQL | Med | `UPDATE investor_units SET deleted_at=NOW() WHERE id=...` |
| Add manual payout | Studio SQL | Med | `INSERT INTO payouts (..., source='manual', ...)` |
| Approve exit | Studio SQL | Med | `UPDATE exit_requests SET status='approved'...` |
| Settle exit (post-approve) | Studio SQL + manual notif | Med — auto-notif silent on this path | `UPDATE...settled` + `INSERT notifications` |
| Approve bank change | Zoho (push) + Studio SQL (flip) | Med | `UPDATE bank_change_requests SET status='approved'...` |
| Unban auth user | Studio Auth UI | Low | "Remove ban" button |
| Kill sessions | Studio SQL | Low | `DELETE FROM auth.refresh_tokens WHERE user_id=...` |
| Password recovery | Studio Auth UI | Low | "Send recovery" button |
| Reset PIN | Studio SQL | Low | `UPDATE user_settings SET app_pin_hash=NULL...` |
| Soft-delete | Studio SQL | High — investor cut off | `UPDATE investors SET deleted_at=NOW()` + ban auth |
| Hard-delete | Studio SQL | CRITICAL — irreversible, audit lost | `DELETE FROM investors WHERE id=...` |

---

## 14. Defects + open questions

### P1 (block ops day-one)

None — the workflow is functional.

### P2 (correctness / data drift)

- **DEF-OPS-1.** `auth.users.email` and `investors.email` can drift. The
  webhook never pushes Zoho email changes to `auth.users`. If a Zoho
  operator changes a contact's email, the investor sees the new email in
  the profile screen but still signs in with the old one. Fix: extend
  `handleContact` in `zoho-crm-webhook` to also call
  `supabase.auth.admin.updateUserById(row.id, { email: d.Email })`.
- **DEF-OPS-2.** Exit request `approved → settled` does NOT fire a
  notification (trigger gates on OLD.status='pending'). The natural ops
  workflow is pending → approved → settled, which means investors never
  get a "settled" notification automatically. Fix: drop the `OLD.status='pending'`
  guard and instead check `NEW.status IS DISTINCT FROM OLD.status` plus
  a status-allowlist.
- **DEF-OPS-3.** `Contacts.Date_of_Birth` and `Contacts.Aadhaar_Number`
  in Zoho are NOT pulled by the webhook. Only the in-app initial-setup
  flow writes those columns. So if Zoho is the master, DOB and Aadhaar
  are inconsistent. Fix: add the Zoho field reads in `handleContact`.
- **DEF-OPS-4.** `LLP_UnitAllocation_Module` delete is not fanned out by
  the webhook. The webhook only handles delete for Contacts and LLPs.
  If Zoho ops cancel an allocation, Supabase still shows it as active
  until ops manually `UPDATE investor_units SET deleted_at=NOW()`. Fix:
  add a `handleAllocationDelete` branch.
- **DEF-OPS-5.** `kyc_resubmissions` has no notification trigger. The
  investor doesn't learn that their re-submission was accepted/rejected
  unless ops also flips `investors.kyc_status` (which DOES fire). The
  two need to be done in lockstep; the resubmission row alone is silent.

### P3 (cosmetic / hygiene)

- **DEF-OPS-6.** `investors.address_line2` column exists but no source
  field is mapped. Dead column.
- **DEF-OPS-7.** `kyc_status` enum allows `in_progress` but the
  notification trigger does not fire on `pending → in_progress` (only
  on terminal states). This is probably intentional but undocumented.

### Open questions

- Is there a planned admin UI on top of Studio? If yes, several of the
  "Studio SQL" recipes above become button clicks.
- Should the webhook push email + phone changes back to `auth.users`?
  Today Zoho is master for the investors row but Studio Auth is master
  for the auth row.
- What's the retention policy for `notifications`? The table has no
  auto-purge. Soft-deleted investor's notifications stay forever.

---

## 15. Migration references

- 002 — `investors` and `projects` base schema, sensitive-field masking columns.
- 003 — `investor_units` and `payouts` base schema.
- 006 — `notifications`, `support_tickets`, `bank_change_requests` base.
- 008 — `portfolio_summary` view (Home "Next Payout" source).
- 026 — `user_settings` (app PIN, biometric/notifications toggles) +
  `login_events` (audit log).
- 027 — Self-onboard write policies on `investors`.
- 028 — `kyc_resubmissions`.
- 029 — `exit_requests` schema and initial RLS.
- 030 (soft-delete) — `deleted_at` columns on `investors`, `llps`, `projects`.
- 034 — Notification triggers (KYC, exit, ticket reply, bank change).
- 042 — `investor_units.deleted_at` + RLS hide.
- 043 — `bank_change_requests.updated_at` (closes a trigger crash from
  migration 010).
- 044 — Exit-request 5-year lock-in RLS WITH CHECK.

Source-of-truth files:

- `supabase/functions/zoho-crm-webhook/index.ts` — the entire sync pipeline.
- `supabase/functions/onboard-investor/index.ts` — invite flow.
- `supabase/migrations/20260513040000_034_notification_triggers.sql` —
  every auto-notification rule the app emits.
- `lib/core/repositories/user_settings_repository.dart` — PIN hashing.
- `lib/core/repositories/investor_repository.dart` — self-onboarding
  upsert (the only Supabase-side legitimate write to PAN / DOB / Aadhaar /
  bank metadata).
