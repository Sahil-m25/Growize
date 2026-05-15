# ARL Investor Portal — Ops & Admin Guide

**Audience.** ARL admin / future ops hire. You can read English and Excel
but you've never deployed code. You'll be editing investor data, LLPs,
allocations, payouts, photos, and documents — without breaking sync.

**Companion docs.**
- `docs/data_flow_guide.md` — full architecture reference. Read it once if
  you're new to the system. Heavier reading.
- `docs/debug_runbook.md` — for engineers when things break at 2am. You
  shouldn't usually need it. It's flagged here when relevant.

**Project ref:** `oynfhdqizebvgmaoiuax`
**Supabase Dashboard:** https://supabase.com/dashboard/project/oynfhdqizebvgmaoiuax
**Zoho CRM (IN data centre):** https://crm.zoho.in/

If anything you read here contradicts the live system, trust the live
system, then ping the engineer and update this doc.

---

## Part 1 — Quick Reference Card

> ⚠️ **Risk legend:** 🟢 safe to repeat • 🟡 review before saving • 🔴 will be clobbered by the next CRM sync OR can break an investor's data.

| Action | Where | Lag | Risk |
|---|---|---|---|
| Update investor display name (First + Last) | Zoho CRM → Contacts → edit `First_Name` / `Last_Name` | ~30s | 🟢 |
| Update investor email | Zoho CRM → Contacts → `Email` | ~30s | 🟡 changes login email; user must use new one |
| Update investor phone | Zoho CRM → Contacts → `Mobile` (preferred) or `Phone` | ~30s | 🟢 |
| Update investor address | Zoho CRM → Contacts → `Mailing_Street/City/State/Zip/Country` | ~30s | 🟢 |
| Mark KYC verified | Zoho CRM → Contacts → `KYC` picklist → `Completed` | ~30s | 🟢 |
| Update bank details (IFSC, branch, name) | Zoho CRM → Contacts → `ISFC_Code`, `Bank_Branch`, `Bank_Name`, etc. | ~30s | 🟡 verify with investor first; this is payout target |
| Update PAN | Zoho CRM → Contacts → `PAN_Number` (auto-masked in app) | ~30s | 🟢 |
| Toggle profile/agreement flags | Zoho CRM → Contacts → `Profile_verified` / `Agreement_signed` checkboxes | ~30s | 🟢 |
| Onboard new investor | (See **Recipe 1**) | ~1 min | 🟡 needs ADMIN_SECRET; email must be real domain |
| Add new LLP | Zoho CRM → LLP_Creation_Module → New | ~30s if UI; up to 24h if API without `trigger:["workflow"]` | 🟡 see "Gotchas" |
| Change LLP status (open/closed/active) | Zoho CRM → LLP_Creation_Module → `LLP_Status` | ~30s | 🟢 also flips marketplace visibility automatically |
| Change project unit price / tier / total units | Zoho CRM → LLP_Creation_Module → `Pet_Unit_Price` / `Tier` / `Total_Units` | ~30s | 🟡 affects future allocations only |
| Allocate units to investor | Zoho CRM → LLP_UnitAllocation_Module → New record | ~30s if UI | 🟡 must include `Name`; see **Recipe** in field glossary |
| Change unit count for existing allocation | Zoho CRM → LLP_UnitAllocation_Module → edit `Issued_Units` / `Reserved_Units` | ~30s | 🟡 verify with finance — overrides allocation history |
| Record new payout (UTR/amount/date) | (See **Recipe 3**) | ~30s | 🟢 |
| Update marketplace tagline / image / sort order / expected return / deadline | Supabase Studio → Table Editor → `projects` row | immediate | 🟢 these columns are NOT in Zoho; safe |
| Toggle marketplace listing manually | (Don't — use `LLP_Status` in Zoho instead) | — | 🔴 will be clobbered on next CRM edit |
| Upload per-investor PDF (agreement, KYC scan) | (See **Recipe 2**) | immediate | 🟢 |
| Upload LLP-wide PDF visible to all investors | (See **Recipe 2** — loop one INSERT per investor) | immediate | 🟡 no native LLP-scope today |
| Upload project photos | Zoho CRM → LLP record → Attachments tab → upload images | next 06:00 IST cron | 🟢 — wait up to 24h |
| Force-fire daily reconcile | curl `…/functions/v1/zoho-reconcile-daily` with `x-arl-cron-secret` header | immediate | 🟢 |
| Force-fire webhook for one record | Run `Push_<X>_To_Supabase` Deluge function in Zoho with the record id | immediate | 🟢 |
| Force-fire gallery sync | curl `…/functions/v1/gallery-sync` with `x-arl-cron-secret` header | immediate | 🟢 |
| Process bank-change request | Read `bank_change_requests` in Studio; verify; then edit Zoho Contact bank fields | bank fields update ~30s post-CRM edit | 🟡 the only way; no admin UI today |
| Mark a payout as "Next Payout" on Home | Supabase Studio → `payouts` row → set `status='pending'` | immediate | 🟡 future cron won't re-flip; do this only for upcoming payouts |
| Maintenance mode ON | Supabase Studio SQL: `UPDATE app_config SET value='true' WHERE key='maintenance_mode';` | next app launch | 🟡 blocks all users — coordinate with team |
| Maintenance mode OFF | Same SQL, `value='false'` | next app launch | 🟢 |
| Force-update prompt | `UPDATE app_config SET value='<vX.Y.Z>' WHERE key='min_app_version';` | next app launch | 🟡 bumping too high locks out users on old builds |
| Read webhook errors | Supabase Studio SQL: `SELECT … FROM webhook_log WHERE status='failed' ORDER BY received_at DESC LIMIT 20;` | — | 🟢 |
| Reset password / resend magic link | Supabase Dashboard → Authentication → Users → click investor → "Send password recovery" | email instant | 🟢 |
| Delete a test investor | Supabase Dashboard → Auth → Users → delete; also `DELETE FROM investors WHERE id=…` | immediate | 🔴 cascade kills their `investor_units` + `payouts`. Do NOT do this for real investors |
| Delete a test LLP | Zoho CRM → delete record + Studio: `DELETE FROM llps WHERE zoho_llp_id=…` (and `projects` + `investor_units` cascade) | immediate | 🔴 cascades — real allocations vanish. Only for fixtures |
| Look up "what does this app screen read from?" | `docs/data_flow_guide.md` §7 | — | 🟢 |

---

## Part 2 — Field Glossary

Every field surfaced in the app, where it comes from, where you edit it,
and the common mistakes to avoid.

### 2.1 Investor identity & contact

These all live on the Zoho Contact and propagate via the `Push_Contact_To_Supabase`
Deluge function → `zoho-crm-webhook` → `investors` table.

**First_Name + Last_Name (Zoho)** → `investors.name` (Supabase) — **Home greeting** + **Profile header**
- The investor's full name, with first letter of first word capitalised on the Home greeting (e.g. `sahil` → `Sahil`).
- Edit in: Zoho CRM → Contacts → record → `First_Name` + `Last_Name`.
- Shown in: Home page top, "Welcome back, Sahil" + Profile page big header.
- Example: First_Name=`sahil`, Last_Name=`Mohite` → app shows `Sahil` on greeting, `sahil Mohite` everywhere else.
- Common mistake: editing `Full_Name` in Zoho. The webhook ignores it unless First+Last are empty.

**Email (Zoho)** → `investors.email` — **Profile email row**
- The login email. Used for magic-link onboarding + password recovery.
- Edit in: Zoho CRM → Contacts → `Email`. **Do not edit in Supabase Studio** — `auth.users.email` won't update and login breaks.
- Common mistake: typo. The system has no validation beyond Supabase's own. A bad email blocks login forever.

**Mobile / Phone (Zoho)** → `investors.phone` — **Profile phone row**
- Investor's phone. Webhook prefers `Mobile` over `Phone` (so put primary in `Mobile`).
- Edit in: Zoho CRM → Contacts → `Mobile`.

**Salutation (Zoho)** → `investors.salutation` — **Profile prefix (e.g. "Mr.")**
- Honorific. Free text in Zoho.

**Mailing_Street / Mailing_City / Mailing_State / Mailing_Zip / Mailing_Country (Zoho)** → `investors.address_line1 / city / state / pincode / country` — **Profile address block**
- Investor's mailing address. The "address_line1" name is misleading — there's no line2 column. Combine into Mailing_Street if needed.
- Common mistake: leaving any of these blank in Zoho will write `""` to Supabase, overwriting any prior good value.

**arl_id** (Supabase only) → `investors.arl_id` — **Profile sub-header "ARL-002"**
- ARL's internal investor code. Set at onboard time and **never changes**. Not in Zoho.
- Edit in: `onboard-investor` body at creation time only.

**zoho_contact_id** (Supabase only) → `investors.zoho_contact_id` — (never shown to investor)
- The link between the Supabase investor and the Zoho Contact. Set at onboard.
- Edit in: `onboard-investor` body. Direct Studio edits will break sync.
- Constraint: must be unique. Trying to link two investors to the same Contact triggers `23505` error.

### 2.2 KYC and verification flags

**KYC picklist (Zoho)** → `investors.kyc_status` — **Profile KYC pill**

| Zoho picklist value | Supabase enum value | Pill colour in app |
|---|---|---|
| `Pending` | `pending` | grey |
| `In Progress` | `in_progress` | yellow |
| `Completed` or `Verified` | `verified` | green |
| `Rejected` | `rejected` | red |
| `Not Started` | `pending` | grey |
| anything else / blank | `pending` | grey |

- Edit in: Zoho CRM → Contacts → `KYC` picklist.
- The webhook maps Zoho's casing/wording to the Supabase enum via `mapKycStatus()`. Don't worry about exact spelling — `mapKycStatus` handles common Zoho variants.

**Profile_verified / Agreement_signed (Zoho checkboxes)** → `investors.profile_verified / agreement_signed` — **Profile checkmark icons**
- Set when an admin has manually reviewed the profile / received signed agreement.
- Edit in: Zoho CRM → Contacts → tick the boxes.

**Unit_allocated / Payment_received / FEMA_Applicable (Zoho)** → same in Supabase — **(internal use; not currently surfaced as pills)**
- Internal status flags. `FEMA_Applicable` is for NRIs.
- Edit in: Zoho CRM checkboxes.
- Common mistake: editing these in Supabase Studio. The webhook compares `=== true` strictly — sending `"true"` (string) becomes `false`.

### 2.3 Bank details (read-only from app's perspective)

> ⚠️ **Investors cannot edit bank fields from the app.** They submit a request via the "Bank-change Request" form. That request lands in `bank_change_requests` table. Ops verifies and edits Zoho.

| Zoho field | Supabase col | App label |
|---|---|---|
| `Bank_Account_Number` | `bank_account_masked` | Bank details (masked: `****1234`) |
| `ISFC_Code` *(sic — Zoho misspells IFSC)* | `bank_ifsc` | IFSC |
| `Bank_Branch` | `bank_branch` | Branch |
| `Account_Holder_Full_name` | `bank_holder_name` | Account holder |
| `Bank_Name` | `bank_name` | Bank |

- The app shows only the last 4 digits of the account; the full number lives in Zoho.
- Edit in: Zoho CRM → Contacts → bank fields.
- Common mistake: `ISFC_Code` is intentional — the Zoho field is literally misspelled this way. Don't try to "fix" it; the webhook reads `d.ISFC_Code` and writes to `bank_ifsc`.

### 2.4 LLP / project metadata

A single Zoho `LLP_Creation_Module` record fans out into BOTH the `llps`
table (legal stuff) AND the `projects` table (operational stuff). The
default project always has `project.id == llp.id` for the 1:1 mapping.

**Name (Zoho)** → `llps.name` AND `projects.name` — **Project card title** + **Detail header**

**LLP_Status picklist (Zoho)** → `llps.llp_status` + `projects.status` — **Status badge on Project card**

| Picklist value | App badge | Listed on Explore tab? |
|---|---|---|
| `Open for Reservation` | Pending | ✅ yes |
| `Open for Issuance` | Pending | ✅ yes |
| `Active` | Active | ❌ no (existing investors only) |
| `Fully Subscribed / Closed` | (no badge) | ❌ no |
| `Darft` *(Zoho's typo, leave as-is)* | (no badge) | ❌ no |

- The "listed on Explore" column is automatic — `is_listed_in_marketplace` is derived from `LLP_Status` by the webhook. **Do not manually toggle the flag** in Supabase Studio; the next CRM edit will revert it.

**Tier (Zoho picklist)** → `projects.tier` — **Card "Tier 25 L"**
- Display tier label, e.g. "25 L". Free-text in DB.

**Total_Units / Units_Issued / Units_Available_to_Issue (Zoho)** → same in `projects` — (used in invariants; not directly on screens)
- How many units the project offers / has issued / has remaining.
- Edit in: Zoho CRM.

**Pet_Unit_Price (Zoho)** *(sic — should be "Per")* → `projects.price_per_unit` — (used in detail math)
- Price per unit at the project level. Allocations carry their OWN `unit_price` (locked at allocation time), so editing this only affects future allocations.

**Launch_Year (Zoho)** → `projects.launch_year` — **Card progress bar input**
- Used to compute contract progress on the Project card: "Month 4 of 60".
- The webhook coerces a bare year like `"2026"` to `2026-01-01`. Full dates pass through.
- Common mistake: editing the column directly in Studio to "fix" Month X of Y. The next webhook will overwrite.
- **Contract length is hardcoded to 5 years (60 months) in the Flutter code.** Cannot be changed in CRM or Supabase — needs a code change.

**Address_Line_1, Address_Line_1_City, Address_Line_1_State_Province, Address_Line_1_Zip_Postal_Code, Address_Line_1_Country_Region** → `llps.registered_*` + `projects.city/state/pincode/country`
- `llps` gets the legal registered address; `projects` gets the farm location (same fields). If the legal address and farm address differ, current schema can't represent both — log it as future work.

**SPOC_1_Full_Name, SPOC_1_Contact_No, SPOC_2_* (Zoho)** → `llps.spoc1_name / spoc1_phone / spoc2_*` — (not surfaced today)
- Single Point of Contact for the LLP. Edit in Zoho.

**Insurance_Provider, Insurance_Policy_No, Insurance_expiry_date, Insured_Amount (Zoho)** → `projects.insurance_*` — (not surfaced today)
- Per-project insurance metadata. Edit in Zoho.

**Marketplace metadata (Supabase-only, NOT in Zoho)**: edit directly in
Studio → Table Editor → `projects` row:

| Column | What | Notes |
|---|---|---|
| `tagline` | Subtitle on Explore card | Free text, ~50 chars |
| `marketplace_image` | Hero image URL or storage path | Use a CDN URL or upload to a public bucket |
| `marketplace_sort_order` | Position in Explore list | Lower = higher up. Default null = sort last |
| `expected_annual_return_pct` | Marketing override on Explore ("X% expected") | Different from the actual `annual_yield_pct`. Use for headline marketing |
| `subscription_deadline` | "Closes on …" date on Explore | DATE column |
| `cover_image_path`, `color_hex`, `accent_hex` | Card chrome | Hex like `#3C5152` |

### 2.5 Unit allocation (the units + the math)

These all live on Zoho `LLP_UnitAllocation_Module` records, one per
(investor × LLP) pair. They propagate via `Push_Allocation_To_Supabase`
Deluge function → webhook → `investor_units` table.

**id (Zoho)** → `investor_units.zoho_allocation_id` — (never shown)
- The upsert key. Don't touch.

**Name (Zoho)** → (not stored in Supabase) — (never shown)
- Mandatory text field on Zoho's side. Zoho's UI auto-generates it. The webhook ignores it.
- Common mistake: programmatic creates without Name fail with `MANDATORY_NOT_FOUND`. UI creates always include it.

**Customer (Zoho lookup → Contact)** → `investor_units.investor_id` — (never shown)
- Links the allocation to an investor. Picked from a dropdown in Zoho.

**LLP (Zoho lookup → LLP_Creation_Module)** → `investor_units.project_id` — (never shown)
- Links the allocation to an LLP (and via 1:1 mapping, the default project).

**Issued_Units (Zoho)** → `investor_units.issued_units` — **Project card "Your Units"**
- The number of units allocated to this investor for this project.
- Edit in: Zoho.
- Common mistake: editing in Supabase Studio. Will be clobbered on next webhook fire.

**Reserved_Units (Zoho)** → `investor_units.reserved_units` — (not surfaced today)
- Soft-held units pending payment confirmation.

**Investment_Date (Zoho)** → `investor_units.investment_date` — **Detail "Invested on" label** (when shown)
- When the allocation was finalised. Date format `YYYY-MM-DD`.

### 2.6 Capital and money fields

The trickiest part. Three Zoho fields look similar but mean different
things. The Supabase column name is the canonical truth; learn the
mapping.

**Per-unit cost — three fields, three meanings:**

| Field | Where | Meaning | Editable |
|---|---|---|---|
| `Pet_Unit_Price` (Zoho project) | `projects.price_per_unit` | Default unit price for the project. Affects future allocations only. | Zoho LLP_Creation_Module |
| `Unit_Price` (Zoho allocation) | `investor_units.unit_price` | Per-unit cost LOCKED at allocation time for this specific investor's allocation. | Zoho LLP_UnitAllocation_Module |
| (computed in UI) | — | Card "Invested" = `capital_invested + token_advance_amount` | Read-only display |

**Capital — three distinct columns, often confused:**

| Field | Column | Plain English | Where shown |
|---|---|---|---|
| `Capital_Invested` (Zoho) | `investor_units.capital_invested` | ₹ actually received against fully-paid units. For fully-Paid allocations, equals `Issued_Units × Unit_Price` | Card "Invested" (added to Token_Advance), Detail "Invested" |
| `Token_Advance_Amount` (Zoho) | `investor_units.token_advance_amount` | Booking deposit paid before full capital. **Added to Capital_Invested in the UI** (so don't double-count) | Card "Invested" |
| `Capital_Outstanding` (Zoho) | `investor_units.capital_outstanding` | ₹ still owed by investor (Partial allocations). 0 for fully-Paid | Financials Capital Account |
| `Capital_Returns` (Zoho) | `investor_units.capital_returns` | Cumulative returns/yield paid back to investor | Financials Earnings Outlook |

**Total amount — receivable vs received:**

| Field | Column | Meaning | How it's computed |
|---|---|---|---|
| `Total_Amount_Receivable` (Zoho) | `investor_units.total_amount_receivable` | Lifetime expected ₹: rent + capital return | **Zoho trigger** computes from `Token_Advance + sum(Amount_1..10)`. Direct writes are reverted |
| `Total_Amount_Received` (Zoho) | `investor_units.total_amount_received` | Cumulative ₹ paid back so far | **Zoho trigger** computes the running total |

> 💡 **Why two columns?** `_receivable` is what the investor will eventually get (the contract terms). `_received` is what they've actually received. The difference = remaining payouts to come.

### 2.7 Yield, rent, payouts

**Three different "yield/return" fields — clarify which goes where:**

| Field | Column | Meaning | Where shown |
|---|---|---|---|
| `Annual_Rental_Yield` (Zoho LLP_Creation_Module) | `projects.annual_yield_pct` | Project baseline annual rental yield (e.g. 18%) | Not currently surfaced |
| `Annual_Rental_Yield` (Zoho LLP_UnitAllocation_Module) | `investor_units.annual_yield_pct` | This specific investor's actual annual yield. Can differ from project baseline | Detail screen yield label, used in `portfolio_summary` average |
| `expected_annual_return_pct` (Supabase-only) | `projects.expected_annual_return_pct` | Admin marketing override on Explore ("X% expected") | Explore card subtitle |

Same Zoho field name — `Annual_Rental_Yield` — but two different sources:
the project-level one in LLP_Creation_Module and the allocation-level one
in LLP_UnitAllocation_Module. The allocation one is the truth for the
specific investor.

The webhook strips the `%` (so Zoho stores `"18%"`, Supabase stores
`18.00` numeric).

**Payouts — the UTR fan-out:**

Each Zoho `LLP_UnitAllocation_Module` record has 10 slots for payouts:
`UTR_1`/`Amount_1`/`Date_1`, `UTR_2`/`Amount_2`/`Date_2`, … up to `UTR_10`/`Amount_10`/`Date_10`.

Each filled triplet becomes one row in the Supabase `payouts` table.
- `idempotency_key` = `<zoho_allocation_id>_payout_<i>`. Prevents duplicates on re-sync.
- `source` = `'crm'` always (for webhook-fed rows). CHECK allows `crm | books | manual`.
- `status` = `'processed'` always (set on insert). CHECK allows `pending | processed | on_hold`.
- The webhook also inserts ONE notification per allocation update with a payout, NOT one per payout.

> ⚠️ **The "Next Payout" tile on Home reads `status='pending'`. The webhook always writes `'processed'`. To make a payout show as "Next Payout", manually flip its status to `'pending'` in Studio.**

### 2.8 Status fields — exact values

**allocation_status** (free-text, no CHECK)
- Common values: `Paid`, `Partial`, `Pending`, `Not Started`. Whatever Zoho's picklist allows.
- Drives the badge on Project detail page and the "Payment Pending" warning banner.
- Edit in Zoho.

**customer_status** (free-text, no CHECK)
- Common values: `Active`, `Inactive`. Free-form.
- Edit in Zoho.

**llp_status** (free-text, mirrors Zoho picklist)
- See §2.4 table above. Drives marketplace visibility.

**kyc_status** (CHECK enforced)
- One of: `pending | in_progress | verified | rejected`. Mapped from Zoho `KYC` picklist by the webhook.
- Direct INSERT/UPDATE in Studio with a non-enum value will fail with Postgres error `23514`.

---

## Part 3 — Step-by-Step Recipes

### Recipe 1 — Onboard a new investor (from scratch)

**Goal:** A new investor signs up, can log in, and sees their portfolio.

#### Step 1: Create the Zoho Contact
1. Open Zoho CRM → Contacts → "+ Create Contact".
2. Fill in:
   - `First_Name` (e.g. `Rahul`)
   - `Last_Name` (e.g. `Sharma`)
   - `Email` — **must be a real domain** (`@gmail.com`, `@agresearchlabs.com`, etc.). **Do NOT use `.test`, `.example`, `.invalid`, `.localhost`** — Supabase Auth rejects these.
   - `Mobile` (preferred over `Phone`)
   - `Salutation` (`Mr.`, `Mrs.`, `Dr.`, etc.)
   - `KYC` → `Pending` (will be updated later)
3. Save.

#### Step 2: Note the Zoho Contact ID
After saving, the URL bar shows something like `…/Contacts/<long-number>`.
Copy that number — that's the **zoho_contact_id**. Looks like `1169101000001586002`.

#### Step 3: Call `onboard-investor`
This sends the magic-link email and creates the matching Supabase row.

Open a terminal (or Postman, or the curl tool of your choice). The
ADMIN_SECRET lives in Supabase Vault — ask the engineer for it, or read
it from Studio → Project Settings → Edge Functions → Secrets.

```bash
curl -i -X POST "https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor" \
  -H "X-ARL-Admin-Secret: <ADMIN_SECRET>" \
  -H "content-type: application/json" \
  -d '{
    "email": "rahul.sharma@example.com",
    "name": "Rahul Sharma",
    "arl_id": "ARL-00143",
    "zoho_contact_id": "1169101000001586002",
    "phone": "9876543210",
    "salutation": "Mr."
  }'
```

**Expected response:** HTTP 200 with `{"investor_id":"<uuid>","arl_id":"ARL-00143","message":"Invite sent — investor will receive a password-setup email"}`.

**If you get HTTP 401:** The ADMIN_SECRET is wrong. Get the correct value.

**If you get HTTP 409:** An investor already exists with that email or zoho_contact_id. Don't re-run — find the existing one.

**If you get HTTP 500 `Email "<addr>" is invalid`:** The TLD is reserved (`.test`, `.example`, etc.). Change it to a real domain in both the Zoho Contact AND the curl payload.

#### Step 4: Verify the row exists in Supabase
Supabase Dashboard → SQL Editor → run:
```sql
SELECT id, email, name, arl_id, zoho_contact_id, phone, kyc_status, onboarded_at
FROM investors
WHERE email = 'rahul.sharma@example.com';
```
Should return one row with `kyc_status='pending'` and `onboarded_at` set to now.

#### Step 5: The investor receives a magic-link email
The email comes from Supabase with subject "Set up your account" (or similar). Investor:
1. Clicks the link.
2. Sets a password.
3. Lands in the Flutter app, logged in.

If they don't see the email: check spam folder, check the email is right in Zoho, then re-send via Dashboard → Authentication → Users → click investor → "Send password recovery".

#### Step 6: From here on it's automatic
Any further edits to the Zoho Contact (KYC status, address, etc.) flow into Supabase via the webhook within ~30 seconds. The investor sees updates next time the app refreshes.

#### Step 7: Allocate them units (link to Recipe in §2.5)
When ready to assign them units in an LLP:
1. Zoho CRM → LLP_UnitAllocation_Module → New record.
2. `Name` (required — Zoho UI auto-fills, e.g. `<arl_id>-<llp_name>-<n>`).
3. `Customer` lookup → the new Contact.
4. `LLP` lookup → the target LLP.
5. `Issued_Units`, `Unit_Price`, `Capital_Invested`, `Investment_Date`, `Annual_Rental_Yield`, `Allocation_Status`, `Customer_Status`.
6. Save. Webhook propagates to `investor_units` within ~30s.

#### Gotchas
- **Don't use `.test` TLD.** Supabase Auth rejects it.
- **Email must be real and active** if you want the investor to actually click the magic link.
- **`arl_id` is permanent.** Once set, it never changes. Pick the next sequential value (`ARL-00xxx`) — there's no auto-generator today.
- **Re-running with the same email** returns HTTP 409. Use the existing investor.
- **Re-running with the same zoho_contact_id** but different email is blocked by a UNIQUE constraint (added 2026-05-11). You'll get HTTP 500 with Postgres error `23505`.

---

### Recipe 2 — Upload a per-investor document

**Goal:** A PDF (agreement, KYC scan, receipt) appears in one investor's Documents tab and nobody else's.

#### Step 1: Get the investor_id
Supabase Dashboard → SQL Editor:
```sql
SELECT id FROM investors WHERE email = '<investor-email>';
```
Copy the UUID. Call it `<investor_id>`.

#### Step 2: Upload PDF to Storage
1. Supabase Dashboard → Storage → click `arl-documents` bucket.
2. Navigate into the `documents/` folder (or create if not present).
3. Create a folder named exactly `<investor_id>` (no quotes, the UUID itself).
4. Inside that folder, click "Upload" → select your PDF.
5. The file's final path will be `documents/<investor_id>/<filename>.pdf`. **The path MUST follow this convention** or RLS will hide it from the investor.

#### Step 3: INSERT into `documents` table
Supabase Dashboard → SQL Editor:
```sql
INSERT INTO documents (
  investor_id,
  project_id,           -- optional: NULL for non-project-specific docs
  doc_type,             -- 'contract' | 'agreement' | 'kyc' | 'other'
  name,                 -- display name shown to the investor
  storage_path,         -- must match the Storage path above
  file_size_kb          -- approximate file size in KB; optional
)
VALUES (
  '<investor_id>',
  NULL,
  'agreement',
  'Investment Agreement - Pineapple Enterprises.pdf',
  'documents/<investor_id>/agreement-pineapple.pdf',
  450
);
```

#### Step 4: Verify
The investor sees the doc next time they open the Documents tab (no refresh logic — the provider re-fetches on each tab visit). Signed URL TTL is **1 hour**, regenerated on each view.

#### Step 5: To delete / replace
- **Replace**: upload new file (same path overwrites), no DB change needed. Or new path + UPDATE `storage_path`.
- **Delete**: `DELETE FROM documents WHERE id='<doc_id>';` (DB row), then delete the file from Storage.

#### File limits
- **Max size**: 50 MiB (`52428800` bytes).
- **Allowed mime types**: `application/pdf`, `image/jpeg`, `image/png`, `image/webp`.
- **Signed URL TTL**: 1 hour (regenerated each time the app fetches).

#### LLP-wide document (visible to all investors of one LLP)
There's no first-class "LLP-scoped doc" feature today. Workaround:

```sql
-- Insert one row per investor allocated to the LLP, all pointing at the same file.
INSERT INTO documents (investor_id, project_id, doc_type, name, storage_path, file_size_kb)
SELECT iu.investor_id, iu.project_id, 'other',
       'Q1 Performance Report - Pineapple Enterprises.pdf',
       'documents/shared/pineapple-q1-2026.pdf',  -- shared path
       890
FROM investor_units iu
WHERE iu.project_id = '<project_id>';
```

Note: Storage RLS will block these reads unless you upload the file to
each investor's folder, OR you use the `service_role` policy to access
files via signed URLs. The simpler way is to upload one file per
investor (yes, duplicate storage). For now, low priority — most docs
are per-investor anyway.

---

### Recipe 3 — Record a new payout

**Goal:** An investor's allocation just got a rent payment / capital return. Record it so the app shows it in the Financials ledger.

#### Step 1: Open the allocation in Zoho
Zoho CRM → LLP_UnitAllocation_Module → find the record by investor name or LLP name. Open it.

#### Step 2: Fill the next unused UTR_N / Amount_N / Date_N triplet
The allocation has 10 slots: `UTR_1`/`Amount_1`/`Date_1` through `UTR_10`/`Amount_10`/`Date_10`.

Find the next slot where all three are empty. Fill in:
- `UTR_N` — bank reference number (string).
- `Amount_N` — rupee amount (e.g. `125000`).
- `Date_N` — payout date.

Save the record.

#### Step 3: Workflow fires; webhook propagates
~30 seconds later, a new row appears in `payouts`:
```sql
SELECT id, utr, amount, payout_date, status, source, created_at
FROM payouts
WHERE allocation_id = (SELECT id FROM investor_units WHERE zoho_allocation_id = '<zoho_allocation_id>')
ORDER BY payout_date DESC;
```

You should see your new entry with `status='processed'`, `source='crm'`.

#### Step 4 (optional): Mark it pending to surface on Home "Next Payout"
The webhook always writes `status='processed'`. If you want this payout to appear in the "Next Payout" tile on the investor's Home screen, flip the status:
```sql
UPDATE payouts SET status = 'pending' WHERE id = '<payout_id>';
```
- Home shows the **earliest** pending payout. So if multiple exist, only the one with the oldest `payout_date` appears.
- After the payout is actually paid, flip back: `UPDATE payouts SET status='processed' WHERE id='<payout_id>';`

#### Step 5: Notification
The webhook also fires ONE notification per allocation update (not per payout). The investor sees:
> "Payout processed — Your payout for <project name> has been processed."

#### Common mistakes
- **Skipping a UTR slot** (filling UTR_3 but leaving UTR_2 blank) creates a gap. The webhook handles it — it just skips empty slots. But the slot numbers are stable: UTR_3 always maps to the third payout slot in Zoho, regardless of whether earlier slots are filled.
- **Clearing a UTR in Zoho** does NOT delete the corresponding `payouts` row. The webhook only INSERTs (never DELETEs). To remove a payout, delete the row directly in Studio:
  ```sql
  DELETE FROM payouts WHERE id = '<payout_id>';
  ```
- **Editing UTR or amount after first save** is allowed in Zoho but the webhook's idempotency key is based on `<zoho_allocation_id>_payout_<i>`, so the row is upserted (replaced). Edits flow through. **But** `ignoreDuplicates: true` in the upsert means existing rows are NOT modified on re-fire. To force-update an existing payout row, DELETE it first.

---

### Recipe 4 — Force-fire a sync (when data looks stale)

**Symptom:** An investor reports they updated something in Zoho an hour ago but the app still shows the old value.

#### Step 1: Check `webhook_log` first
Supabase Dashboard → SQL Editor:
```sql
SELECT received_at, status, event_type, zoho_record_id, error_message
FROM webhook_log
WHERE received_at > NOW() - INTERVAL '2 hours'
ORDER BY received_at DESC
LIMIT 20;
```

**If you see a recent matching event** with `status='processed'`: the webhook ran. The app might be showing cached data — ask the investor to pull to refresh.

**If you see `status='failed'`**: read the `error_message`. Common ones:
- `investors update failed: …` — see `docs/debug_runbook.md` "Common errors".
- `MANDATORY_NOT_FOUND` / numeric / date syntax errors — schema mismatch, escalate.

**If you see NO matching event**: the webhook didn't fire. Most likely the Zoho workflow rule is disabled OR the record was created via API without `trigger:["workflow"]`. Continue to Step 3.

#### Step 2: Reach for the debug runbook
For non-trivial errors, hand off to engineering. `docs/debug_runbook.md` has the deep-dive playbook.

#### Step 3: Manually fire reconcile-daily (full sweep)
This pulls all CRM records modified in the last 25 hours and upserts them. Catches anything the webhook missed.

```bash
curl -i -X POST "https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily" \
  -H "x-arl-cron-secret: <CRON_SECRET>"
```

The CRON_SECRET lives in Vault as `cron_secret`. Ask the engineer or read from Studio.

**Expected response:** HTTP 200 with `{"status":"ok","contacts":{"scanned":N,"updated":M},"llps":{...},"allocs":{...}}`.

Run-time is usually 5-30 seconds. If it returns 500, read the `error` field.

#### Step 4: Manually fire single-record webhook (Deluge function)
In Zoho CRM → Setup → Developer Hub → Functions → find one of:
- `Push_Contact_To_Supabase`
- `Push_LLP_To_Supabase`
- `Push_Allocation_To_Supabase`

Click "Run". Enter the recordId of the record you want to re-sync. Click Execute.

This sends one payload directly to the webhook for that specific record. Faster than waiting for reconcile if you only need one row.

#### Step 5: For gallery photos specifically
```bash
curl -i -X POST "https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/gallery-sync" \
  -H "x-arl-cron-secret: <CRON_SECRET>"
```
Polls Zoho CRM Attachments for every LLP and copies new images into Storage.

#### Step 6: Verify
Query the relevant table again. The row should now reflect Zoho's current state. If not, escalate to engineering with the webhook_log entry.

---

### Recipe 5 — Maintenance mode / app gate

**When to use:** Doing a risky deploy, fixing a bad data corruption, or anything where you want all investors to see "back soon" instead of broken data.

#### Step 1: Turn maintenance mode ON
Supabase Dashboard → SQL Editor:
```sql
UPDATE app_config SET value = 'true' WHERE key = 'maintenance_mode';
```

#### Step 2: What investors see
Next app launch shows the Maintenance screen (`lib/features/gating/maintenance_screen.dart`) with a "Retry" button. They cannot use any other part of the app.

Already-running app sessions also poll `app_config` periodically; expect new launches to be blocked within ~30 seconds.

#### Step 3: Turn maintenance mode OFF when done
```sql
UPDATE app_config SET value = 'false' WHERE key = 'maintenance_mode';
```

#### Force-update prompt (less aggressive)
If you've shipped a new version and want to force users to upgrade:
```sql
UPDATE app_config SET value = '<vX.Y.Z>' WHERE key = 'min_app_version';
```
Investors on builds below this see a "Please update" screen with a link to the store. They cannot proceed until they upgrade.

Soft-prompt only (suggested, not forced):
```sql
UPDATE app_config SET value = '<vX.Y.Z>' WHERE key = 'latest_app_version';
```

#### Show a custom message during maintenance
```sql
UPDATE app_config SET value = 'Back at 5 PM IST. Sorry for the inconvenience.' WHERE key = 'maintenance_message';
```
Shown on the maintenance screen below the icon.

#### Common mistake
- **Bumping `min_app_version` to a value higher than any deployed build** locks everyone out, including testers. Roll back: `UPDATE app_config SET value='1.0.0' WHERE key='min_app_version';`

---

### Recipe 6 — Allocate units to an existing investor

**Goal:** A previously-onboarded investor takes units in an LLP. They'll see the project on their Home + Projects + Financials.

#### Prerequisites
- Investor already onboarded (row exists in `investors`). If not, run **Recipe 1** first — `handleAllocation` returns silently if the investor isn't found, and the allocation ends up orphaned in CRM.
- Target LLP exists in Zoho AND has been synced to `llps` + `projects` in Supabase. If you just created the LLP, verify with **Recipe 4 Step 1** before allocating.

#### Step 1: Copy the Zoho Contact ID
1. Zoho CRM → Contacts → open the investor's record.
2. URL bar shows `…/Contacts/<long-number>`. Copy the number, e.g. `1169101000001586002`.

#### Step 2: Copy the Zoho LLP ID
1. Zoho CRM → LLP_Creation_Module → open the LLP record.
2. URL bar shows `…/LLP_Creation_Module/<long-number>`. Copy it, e.g. `1169101000001586010`.

#### Step 3: Create the allocation record
Zoho CRM → LLP_UnitAllocation_Module → "+ Create".

| Field | Value | Notes |
|---|---|---|
| `Name` | `<arl_id>-<short_llp>-<seq>` (e.g. `ARL-00143-Pineapple-1`) | **MANDATORY**. Zoho's UI auto-fills, but check it's present. Free text |
| `Customer` (lookup) | pick the investor from the picker | Backed by Zoho Contact ID |
| `LLP` (lookup) | pick the LLP from the picker | Backed by Zoho LLP_Creation_Module ID |
| `Issued_Units` | e.g. `5` | Number of units the investor is buying |
| `Unit_Price` | e.g. `2500000` (for 25 L tier) | ₹ per unit locked at this allocation's time |
| `Capital_Invested` | e.g. `12500000` (5 × 25L) | Capital received against the units |
| `Allocation_Status` | `Paid` (or `Partial`, `Pending`) | Drives Detail badge + "Payment Pending" banner |
| `Customer_Status` | `Active` | Drives Detail status pill |
| `Investment_Date` | today's date `YYYY-MM-DD` | Or back-date if appropriate |
| `Annual_Rental_Yield` | e.g. `18%` | Per-allocation actual yield. Webhook strips the `%` |
| `Reserved_Units` | `0` typically | Soft-held units pending payment |
| `Capital_Outstanding` | `0` for Paid allocations | Balance owed |
| `Token_Advance_Amount` | `0` typically | Pre-payment deposit |
| `UTR_1` / `Amount_1` / `Date_1` | leave blank initially | Fill later when first payout happens (Recipe 3) |

Save.

#### Step 4: Workflow fires
The "Supabase Sync - LLP Allocation" workflow rule (Zoho) calls
`Push_Allocation_To_Supabase` → `zoho-crm-webhook` → `handleAllocation` →
upsert into `investor_units`. Takes ~30 seconds.

#### Step 5: Verify
```sql
SELECT id, zoho_allocation_id, investor_id, project_id,
       issued_units, capital_invested, allocation_status, customer_status,
       investment_date, annual_yield_pct, last_synced_at
FROM investor_units
WHERE zoho_allocation_id = '<copy from Zoho create response>';
```
You should see one row with the values you entered, plus `investor_id` resolved to the right `investors.id` and `project_id` resolved to the default `projects` row for the LLP.

#### Step 6: Investor sees it
Next time the investor opens the Flutter app:
- **Home** — portfolio totals include the new units + invested capital.
- **Projects** — new card appears with "Your Units" + "Invested".
- **Financials** — Capital Account picks up the new allocation.

No app refresh logic needed; providers re-fetch on each tab visit.

#### Common mistakes
- **Forgot to onboard the investor first.** Allocation lands in CRM but `handleAllocation` returns silently (no investors row to link). The allocation is orphaned. Fix: onboard the investor (Recipe 1), then **Recipe 4 Step 4** to manually re-fire the Allocation webhook so the row finally lands.
- **Forgot `Name` field on programmatic create.** Zoho returns 400 `MANDATORY_NOT_FOUND`. UI creates always include Name; API/Postman creates don't.
- **Programmatic create without `trigger:["workflow"]`.** The Supabase Sync workflow won't fire. The allocation lives in CRM but not in Supabase. Fix: pass the trigger flag, OR rely on the daily reconcile (01:00 UTC), OR manually fire (**Recipe 4 Step 4**).
- **Allocation_Status as `Verified` or other non-standard text.** Free-text column accepts anything, but the app's "Payment Pending" banner specifically matches `Pending` and `Partial`. Use exact Zoho picklist values.

---

### Recipe 7 — Add a new LLP that appears in Marketplace

**Goal:** A new investment offering shows up on the Explore tab for all
investors to discover. New investors can browse + express interest.

#### Step 1: Create the LLP in Zoho
Zoho CRM → LLP_Creation_Module → "+ Create".

| Field | Value | Notes |
|---|---|---|
| `Name` | `Citrus Grove LLP` (or similar) | Display name |
| `LLP_Status` | `Open for Reservation` OR `Open for Issuance` | **These two statuses auto-list it on Explore.** Anything else (`Active`, `Fully Subscribed / Closed`, `Darft`) will NOT list it |
| `Tier` | `25 L` (etc.) | Picklist for unit price tier |
| `Total_Units` | e.g. `120` | Total units the project will offer |
| `Pet_Unit_Price` | e.g. `2500000` | ₹ per unit |
| `Total_Ticket_Size` | e.g. `2500000` | Min entry for one investor |
| `Total_Project_Cost` | e.g. `300000000` (30 Cr) | Total capex |
| `Acreage_Acres` | e.g. `10` | Farm size |
| `Annual_Rental_Yield` | `18%` | Project baseline yield |
| `Launch_Year` | `2026-01-01` (date) OR `2026` (4-digit year — webhook coerces to Jan 1) | Drives contract progress bar |
| `Address_Line_1` / `Address_Line_1_City` / `Address_Line_1_State_Province` / `Address_Line_1_Zip_Postal_Code` / `Address_Line_1_Country_Region` | Farm location | Shown on Detail subtitle |
| `SPOC_1_Full_Name` / `SPOC_1_Contact_No` | LLP point of contact | Not surfaced today, but stored |
| `GST` / `PAN` / `Incorporation_No` | LLP legal IDs | Stored, not surfaced |
| `Insurance_Provider` / `Insurance_Policy_No` / `Insurance_expiry_date` / `Insured_Amount` | Insurance metadata | Stored, not surfaced |

Save.

#### Step 2: Workflow fires; rows created
Within ~30 seconds:
- `llps` table gets a new row (legal metadata).
- `projects` table gets a new row with `id = llp.id` (operational metadata).
- **`is_listed_in_marketplace` is auto-set to `true`** because `LLP_Status` ∈ {`Open for Reservation`, `Open for Issuance`}.

Verify:
```sql
SELECT id, name, llp_status, is_listed_in_marketplace, last_synced_at
FROM llps l
JOIN projects p ON p.id = l.id
WHERE zoho_llp_id = '<copy from Zoho create response>';
```

#### Step 3: Enrich marketplace presentation
The marketplace display fields are NOT in Zoho — admin sets them
directly in Supabase Studio.

```sql
UPDATE projects SET
  tagline                    = 'Premium citrus farming, 5-year lock-in',
  marketplace_image          = 'https://example.com/path/to/citrus-hero.jpg',
  marketplace_sort_order     = 10,
  expected_annual_return_pct = 18.5,
  subscription_deadline      = '2026-12-31',
  cover_image_path           = 'covers/citrus-grove.jpg',
  color_hex                  = '#3C5152',
  accent_hex                 = '#D4AF37'
WHERE zoho_llp_id = '<id>';
```

| Column | Effect |
|---|---|
| `tagline` | Subtitle on Explore card |
| `marketplace_image` | Hero image (use full HTTPS URL or storage path) |
| `marketplace_sort_order` | Lower = higher up in Explore list. Default NULL = last |
| `expected_annual_return_pct` | Headline "X% expected" — **marketing override**, can differ from actual `annual_yield_pct` |
| `subscription_deadline` | "Closes on …" countdown |
| `cover_image_path` / `color_hex` / `accent_hex` | Card chrome on the Projects list |

#### Step 4: Verify in the app
Open the Flutter app's Explore tab. The new LLP appears in the list,
sorted by `marketplace_sort_order` ascending.

#### Step 5: To drop the LLP from Marketplace later
Just change `LLP_Status` in Zoho to `Fully Subscribed / Closed`. The
webhook automatically sets `is_listed_in_marketplace=false` on next
sync. **Don't manually toggle the flag in Studio** — it'll be reverted
on the next CRM edit (the column is now derived, not admin-controlled).

---

### Recipe 8 — Update a project's photos (Gallery)

**Goal:** A new batch of farm photos appears in the Gallery tab for
investors allocated to a specific LLP.

#### Step 1: Upload to Zoho
1. Zoho CRM → LLP_Creation_Module → open the LLP record.
2. Scroll down to the **Attachments** related list (right sidebar usually).
3. Click "Attach" → upload one or more image files (`.jpg`, `.jpeg`, `.png`, `.webp`).
4. Repeat for as many photos as needed.

#### Step 2: Wait for the daily cron
The `gallery-sync` Edge Function runs at **06:00 IST** every day. It:
1. Lists all active LLPs in Supabase.
2. For each, polls Zoho's Attachments endpoint.
3. Downloads new attachments (filters to image mime types).
4. Uploads them to the `arl-gallery` Storage bucket at `gallery/<project_id>/<zoho_file_id>.<ext>`.
5. INSERTs a row in `gallery_photos`.

Idempotency via `gallery_photos.zoho_file_id UNIQUE` — same image won't sync twice.

#### Step 3: Force the sync now (if you can't wait until tomorrow)
```bash
curl -i -X POST "https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/gallery-sync" \
  -H "x-arl-cron-secret: <CRON_SECRET>"
```
Expected: HTTP 200 with `{"status":"ok","totalNewPhotos":N,"affectedProjectIds":[…]}`.

#### Step 4: Verify
```sql
SELECT COUNT(*) AS photo_count, MAX(uploaded_at) AS most_recent
FROM gallery_photos
WHERE project_id = '<project_uuid>';
```

Or visually: SQL Editor query:
```sql
SELECT id, caption, storage_path, uploaded_at
FROM gallery_photos
WHERE project_id = '<project_uuid>'
ORDER BY uploaded_at DESC;
```

#### Step 5: Investors see them
Investors allocated to the LLP (via any `investor_units` row pointing
at this `project_id`) see the new photos in their Gallery tab next
time they open the app. Signed URLs are 1h TTL.

#### Gotchas
- **Photos are LLP-wide.** Any investor with allocation on the LLP sees them. There's no per-investor photo gating today.
- **Deleting a photo from Zoho does NOT delete it from Supabase.** The `gallery-sync` function is INSERT-only. To remove a photo:
  ```sql
  DELETE FROM gallery_photos WHERE id = '<photo_id>';
  ```
  Then manually delete the file from the Storage bucket (`arl-gallery` → navigate to `gallery/<project_id>/` → delete file).
- **Storage bucket path**: `arl-gallery/gallery/<project_id>/<zoho_file_id>.<ext>`. The `zoho_file_id` is what Zoho assigns the attachment; visible in `gallery_photos.zoho_file_id`.
- **Max file size**: 10 MiB per image (`arl-gallery` bucket limit, configured in migration 013).
- **Allowed mime types**: `image/jpeg`, `image/png`, `image/webp`. Other formats (`.gif`, `.heic`) will be skipped.

---

### Recipe 9 — Process a bank-change request

**Goal:** An investor has requested a change to their payout bank
account. Verify, approve, and propagate to Zoho so payouts go to the
right place.

#### Background
Investors cannot edit bank details directly in the app. They submit a
request via the Bank Details screen → the `bank-change-request` Edge
Function inserts a row in `bank_change_requests` (status=`pending`) and
emails ops. There's a 7-day cooldown: an investor with one already-
pending request is throttled until it's resolved.

#### Step 1: View pending requests
Supabase Dashboard → SQL Editor:
```sql
SELECT id, investor_id, status, created_at,
       new_account_holder_name, new_bank_name, new_ifsc, new_account_number_masked,
       resolution_notes
FROM bank_change_requests
WHERE status = 'pending'
ORDER BY created_at;
```

Cross-reference the `investor_id` with the `investors` table to get the investor's name/email:
```sql
SELECT bcr.*, i.name, i.email
FROM bank_change_requests bcr
JOIN investors i ON i.id = bcr.investor_id
WHERE bcr.status = 'pending';
```

#### Step 2: Verify against the investor
- Call the investor on the phone number in `investors.phone`.
- Confirm the new bank details match what they intend.
- Optionally check supporting docs (cancelled cheque, bank statement) if uploaded separately (no integration today; ask via email/Slack).

#### Step 3 (approved): Update Zoho Contact bank fields
1. Zoho CRM → Contacts → open the investor's record.
2. Update:
   - `Bank_Account_Number` (full number, will be auto-masked when synced)
   - `ISFC_Code` (note Zoho's spelling — leave as-is)
   - `Bank_Branch`
   - `Account_Holder_Full_name`
   - `Bank_Name`
3. Save. Webhook propagates to `investors.bank_*` within ~30s.

#### Step 4: Mark the request resolved
```sql
UPDATE bank_change_requests
SET status        = 'approved',
    resolved_at   = NOW(),
    resolved_by   = '<your name or admin handle>',
    resolution_notes = 'Verified by phone, updated Zoho on 2026-05-11.'
WHERE id = '<request_id>';
```

#### Step 5 (rejected): Mark as rejected
```sql
UPDATE bank_change_requests
SET status           = 'rejected',
    resolved_at      = NOW(),
    resolved_by      = '<your name>',
    resolution_notes = 'Account holder name mismatch with PAN; asked investor to resubmit with correct details.'
WHERE id = '<request_id>';
```

The investor sees the "pending" badge clear from their Bank Details screen on next app launch; they can submit a new request after 7 days (cooldown enforced server-side).

#### Step 6: Verify the new bank details landed in Supabase
```sql
SELECT name, bank_account_masked, bank_ifsc, bank_branch, bank_holder_name, bank_name, last_synced_at
FROM investors
WHERE id = '<investor_id>';
```

#### Common mistakes
- **Editing `investors.bank_*` directly in Studio**: the next CRM webhook will clobber it. Always go through Zoho.
- **Forgetting to resolve the request**: the row stays `pending`, but it doesn't actually block the investor any more once bank fields are updated in Zoho. Just untidy data. Resolve for cleanliness.
- **Approving without phone verification**: opens the door to social-engineering attacks. Always verify out-of-band.

There is no admin UI for this flow today. All via Studio + Zoho.

---

### Recipe 10 — Update marketplace presentation

**Goal:** Tweak how a project appears in the Explore tab — change its
tagline, hero image, sort order, expected return %, or subscription
deadline. These fields don't live in Zoho.

#### Step 1: Find the project
Supabase Dashboard → SQL Editor:
```sql
SELECT id, name, status, is_listed_in_marketplace, marketplace_sort_order
FROM projects
WHERE name ILIKE '%pineapple%';   -- substring match
```

Copy the `id` UUID for the project you want to edit.

#### Step 2: Update marketplace fields
```sql
UPDATE projects SET
  tagline                    = 'Premium agri investment, 5-year lock-in',
  marketplace_image          = 'https://example.com/path/to/hero.jpg',
  marketplace_sort_order     = 1,                    -- 1 = top of Explore list
  expected_annual_return_pct = 18.0,
  subscription_deadline      = '2026-12-31',
  cover_image_path           = 'covers/pineapple.jpg',
  color_hex                  = '#3C5152',
  accent_hex                 = '#D4AF37'
WHERE id = '<project_uuid>';
```

#### Step 3: Verify
Open the Flutter app's Explore tab. Changes appear immediately — no
refresh logic needed.

#### Field meanings (cheat-sheet)
| Column | What | Format |
|---|---|---|
| `tagline` | Card subtitle on Explore | Free text, ~50 chars |
| `marketplace_image` | Hero image displayed full-width on the card | Full HTTPS URL preferred. Storage path also accepted |
| `marketplace_sort_order` | Order in Explore list (ascending) | Integer. Lower = higher up. NULL = sorted last |
| `expected_annual_return_pct` | Marketing line "X% expected" on Explore card | NUMERIC. **This is separate from `annual_yield_pct`** — use it for headline marketing, while `annual_yield_pct` reflects actual per-allocation yield |
| `subscription_deadline` | "Closes on …" countdown on the card | DATE column, e.g. `'2026-12-31'` |
| `cover_image_path` | Background image on the Projects card | Storage path or URL |
| `color_hex` | Main brand colour for the project card | `'#3C5152'` |
| `accent_hex` | Secondary brand colour | `'#D4AF37'` |

#### Why this is special
These columns are **Supabase-only** — they're NOT in Zoho CRM. So they're
the exception to the general "don't touch projects in Studio" rule.
Future Zoho edits to the LLP will NOT clobber these values.

#### Common mistakes
- **Using `expected_annual_return_pct` and `annual_yield_pct` interchangeably**: they're different. `expected_annual_return_pct` is admin-controlled marketing copy. `annual_yield_pct` (on `investor_units`) is the actual yield rate from the allocation. Don't sync them.
- **Linking `marketplace_image` to a Storage path with no public access**: if you upload to a private bucket, the image won't load. Either use a public CDN URL, or use a Storage bucket with public read access (Storage RLS policy `SELECT` for `public` role).
- **Setting `marketplace_sort_order = 0` thinking 0 means "no sort"**: 0 means "first". NULL means "sort last".

---

## Part 4 — DON'T TOUCH list + gotchas

> 🔴 **Never edit these in Supabase Studio.** The next CRM sync (real-time webhook or daily reconcile) will clobber your change.
>
> **investors:**
> - `name`, `email`, `phone`, `salutation`
> - `kyc_status`
> - `pan_masked`, `bank_account_masked`, `bank_ifsc`, `bank_branch`, `bank_holder_name`, `bank_name`
> - `address_line1`, `city`, `state`, `pincode`, `country`
> - `unit_allocated`, `payment_received`, `profile_verified`, `agreement_signed`, `fema_applicable`
>
> **llps:** all CRM-sourced columns (`name`, `llp_status`, `llp_owner`, `incorporation_no`, `gst`, `pan`, `registered_*`, `spoc1_*`, `spoc2_*`).
>
> **projects:** all CRM-sourced columns (`name`, `status`, `tier`, `total_units`, `units_issued`, `units_available`, `price_per_unit`, `total_project_cost`, `total_ticket_size`, `acreage_acres`, `annual_yield_pct`, `launch_year`, `insurance_*`, `is_listed_in_marketplace`).
>
> **investor_units:** `issued_units`, `reserved_units`, `unit_price`, `capital_invested`, `capital_outstanding`, `capital_returns`, `total_amount_receivable`, `total_amount_received`, `token_advance_amount`, `annual_yield_pct`, `allocation_status`, `customer_status`, `investment_date`, `next_payout_date`.
>
> **payouts:** the core fields `utr`, `amount`, `payout_date`. (Status flip allowed for "Next Payout" surfacing; see Recipe 3.)

> 🟢 **Marketplace fields you CAN edit in Studio** (not in Zoho — these are display-only):
> - `projects.tagline`
> - `projects.marketplace_image`
> - `projects.marketplace_sort_order`
> - `projects.expected_annual_return_pct`
> - `projects.subscription_deadline`
> - `projects.cover_image_path`, `color_hex`, `accent_hex`
>
> **Exception summary:** `projects.tagline`, `marketplace_image`, `marketplace_sort_order`, `expected_annual_return_pct`, `subscription_deadline`, `cover_image_path`, `color_hex`, `accent_hex` are the **only** `projects` columns safe to edit in Studio — they are not in CRM. Every other `projects` column will be clobbered on the next CRM sync.

### Other gotchas

- **Currency**: INR only. Formatting is `₹X.XX L` below 1 crore, `₹X.XX Cr` at or above. Hardcoded.
- **Contract length**: hardcoded 5 years (60 months) in the Flutter `Project.fromSupabase` factory. Can't be changed in CRM or Supabase. Needs code change.
- **Daily reconcile cron** runs at **01:00 UTC = 06:30 IST**. Late-night IST edits (after 6:30 AM IST) will reconcile in the same morning's run if the webhook missed. Otherwise next day 06:30 IST.
- **Gallery photos** lag up to 24 hours. The cron is at **06:00 IST**. Force-fire with curl if needed (Recipe 4 Step 5).
- **`.test` TLD** is blocked by Supabase Auth. Use real domains. Magic-link email can bounce; the auth user is still created.
- **Programmatic Zoho creates** (Postman, API scripts, MCP) skip workflow rules unless `trigger:["workflow"]` is in the body. UI creates always fire. If you need to trigger sync from an API caller, set the trigger flag OR rely on next daily reconcile.
- **`LLP_UnitAllocation_Module.Name` is mandatory on programmatic creates.** UI creates auto-fill via auto-number. API creates without `Name` fail with `MANDATORY_NOT_FOUND`.
- **Soft deletes in Zoho don't propagate.** A record deleted in CRM stays in Supabase forever. Manual cleanup needed (`DELETE FROM <table> WHERE …`).
- **Notifications are payout-only today.** No way to broadcast a marketing or maintenance notification to all investors. The `notifications.type` CHECK has `photo | ticket | reminder | milestone` reserved for the future but unused.
- **`investor_units.allocation_status` is free-text.** Use exact Zoho picklist values: `Paid`, `Partial`, `Pending`, `Not Started`. The app's "Payment Pending" banner triggers on `Pending` or `Partial` specifically (case-sensitive).
- **`is_listed_in_marketplace` is derived from `LLP_Status`.** Manually flipping it in Studio will be reverted on the next CRM edit of that LLP. If you really need to force-list/unlist, change the `LLP_Status` instead.
- **Token_Advance_Amount counts toward "Invested"** in the Projects card UI. Don't double-count it in spreadsheet math against `Capital_Invested`.
- **The bank-change-request flow has no admin UI.** Investors submit via app → row lands in `bank_change_requests` → ops verifies via SQL → ops edits Zoho Contact → webhook propagates. Manual every time.
- **Support tickets have no admin reply UI.** Investors reply via the app's `reply-ticket` function. Ops would need to insert into `ticket_messages` directly in Studio (with `is_staff=true` if that flag exists — check the schema).
- **Idempotency keys persist forever.** `webhook_log.idempotency_key`, `payouts.idempotency_key` are UNIQUE. Re-firing the same event is safe; it returns "duplicate" without re-processing.

---

## Part 5 — Glossary

| Term | Meaning |
|---|---|
| **ARL** | AgResearch Labs — the operating company. |
| **ZCID** | Shorthand for `zoho_contact_id` — the Zoho CRM-internal record ID of a Contact, used as the link between Supabase `investors` and Zoho `Contacts`. |
| **LLP** | Limited Liability Partnership — the legal entity that owns a farm project. One LLP = one project (1:1 default). |
| **RLS** | Row-Level Security — Postgres feature that filters which rows a user can see/edit based on their auth identity. Every investor-facing table has RLS enabled; service-role bypasses. |
| **KYC** | Know Your Customer — investor identity verification. Status: `pending | in_progress | verified | rejected`. |
| **FEMA** | Foreign Exchange Management Act — applies to NRI investors. The `fema_applicable` boolean. |
| **UTR** | Unique Transaction Reference — bank's reference number for a payout. One per row in `payouts`. |
| **Vault** | Supabase's encrypted secrets store. Used for `ADMIN_SECRET`, `WEBHOOK_SECRET`, `CRON_SECRET`, `ZOHO_*`. |
| **Connection** | Zoho's term for a stored OAuth/API integration. `supabase_webhook_secret` is the Connection that auto-injects the `X-ARL-Webhook-Secret` header. |
| **Deluge** | Zoho's proprietary scripting language. The `Push_<X>_To_Supabase` functions are written in Deluge and called by workflow rules. |
| **Edge Function** | A Deno-based serverless function hosted by Supabase. We run several: `zoho-crm-webhook`, `zoho-reconcile-daily`, `gallery-sync`, `health-check`, `sync-stale-alert`, `onboard-investor`, `create-ticket`, `reply-ticket`, `bank-change-request`. |
| **Storage bucket** | Supabase Storage container. We have two: `arl-documents` (PDFs, 50 MiB limit) and `arl-gallery` (images, 10 MiB limit). Both private. |
| **Signed URL** | A time-limited URL that lets the Flutter app fetch a Storage file without authenticating to Storage directly. TTL = 1 hour. Re-generated on each app load. |
| **Idempotency key** | A unique identifier on a webhook event or payout that prevents the same event from being processed twice. Format: `<module>_<recordId>_<modifiedTime>` for webhook events, `<allocationId>_payout_<i>` for payouts. |
| **Service role** | The Supabase JWT identity that bypasses all RLS. Used by edge functions; never exposed to investors. |
| **Authenticated role** | The Supabase JWT identity granted to a logged-in investor. RLS applies. |
| **Anon role** | Public/unauthenticated access. RLS applies; almost nothing accessible. |
| **Pull-side reconcile** | The daily cron that re-pulls all Zoho records and upserts to catch anything the push webhook missed. Runs 01:00 UTC. |
| **Push webhook** | The real-time webhook fired by Zoho workflow rules. Calls `zoho-crm-webhook` edge function. |
| **portfolio_summary** | Postgres view that aggregates an investor's totals (units, invested, ROI, next payout) for the Home + Financials screens. Defined in migration 015 with `SECURITY INVOKER` so RLS applies. |
| **isListedInMarketplace** | Helper in both webhook + reconcile that derives the `projects.is_listed_in_marketplace` flag from `LLP_Status`. True when `Open for Reservation` or `Open for Issuance`. |
| **Maintenance mode** | App-wide gate controlled by `app_config.maintenance_mode='true'`. Shows the Maintenance screen on all clients. |
| **Token advance** | Booking deposit paid by an investor before the full unit cost. Lives in `Token_Advance_Amount` (Zoho) / `token_advance_amount` (Supabase). Added to `capital_invested` in the UI's "Invested" label. |
| **Mints** | (informal) The act of allocating new units to an investor — creating a Zoho `LLP_UnitAllocation_Module` record. |
| **Reconcile lag** | The worst-case delay before a Zoho change appears in Supabase if the webhook didn't fire. Currently ≤24h (cron runs daily at 01:00 UTC). |

---

## Part 6 — Recent Feature Additions (May 2026)

Five investor-facing features moved from Fail/Partial to Pass on **2026-05-12**. They're documented here in ship order. New tables in this release: `user_settings`, `login_events`, `consultation_requests`, `exit_requests`. The `investors` table also gained client-side INSERT/UPDATE policies for self-onboarding. None of these are sourced from Zoho — they're Supabase-native, written from the Flutter app.

> ⚠️ All four new tables have RLS enabled and policies that scope reads/writes to `auth.uid()`. ARL ops reads/updates via Supabase Studio (service_role bypasses RLS). There is no admin UI yet — triage is SQL today.

### 6.1 Security & PIN (SecurityScreen)

**User journey.** Investor opens app → Profile tab → **Security**. Sees three toggles in one card: **Biometric Login** (off by default — enabling it routes through §6.2), **App PIN** (tap to set/change/remove), **Notifications**. Below the toggles is a **Login History** card listing recent sign-ins with timestamp + device, and a **Last login** stamp under Session. All three rows now persist across sessions and devices.

**App PIN handling.** The PIN itself is hashed **on the device** using a 16-byte random salt + 100 000 iterations of SHA-256. Only the salt + iteration count + digest reach the database. **Plaintext PINs never leave the phone** and are not present in any log, network capture, or table. Changing or removing a PIN requires the current PIN to be entered first.

**Data model.** Migration `026_user_settings_and_login_events.sql` adds two tables:

| Table | Key columns | RLS |
|---|---|---|
| `public.user_settings` | `user_id PK→auth.users`, `biometric_enabled`, `notifications_enabled`, `app_pin_hash`, `app_pin_salt`, `app_pin_iterations`, `updated_at` | SELECT / INSERT / UPDATE where `user_id = auth.uid()` |
| `public.login_events` | `id`, `user_id→auth.users`, `occurred_at`, `device_label`, `platform`, `app_version`, `user_agent` | SELECT / INSERT where `user_id = auth.uid()`. No UPDATE/DELETE policy = append-only from the client. |

`login_events` is written automatically on every `AuthChangeEvent.signedIn` (real sign-in, not a session refresh). Index: `(user_id, occurred_at DESC)`.

**Ops actions.**
- Audit an investor's recent sign-ins (Supabase Studio → SQL editor):
  ```sql
  SELECT occurred_at, device_label, platform, app_version
  FROM public.login_events
  WHERE user_id = (SELECT id FROM public.investors WHERE email = 'jane@example.com')
  ORDER BY occurred_at DESC
  LIMIT 30;
  ```
- Check whether an investor has set a PIN: `SELECT app_pin_hash IS NOT NULL AS pin_set FROM public.user_settings WHERE user_id = …`. Investors who haven't visited Security yet have no `user_settings` row — that's normal.
- **DON'T** touch `app_pin_hash` / `app_pin_salt` / `app_pin_iterations` manually. If an investor forgets their PIN, deleting the three columns is the recovery (their next entry to the Security screen treats it as unset). There is no way to recover the original PIN — it's only stored as a hash.

**Migration.** `026` — 2026-05-12. Rollback: `DROP TABLE public.user_settings; DROP TABLE public.login_events;`.

---

### 6.2 Biometric enrollment gate (BiometricScreen)

**User journey.** From the SecurityScreen (§6.1), toggling **Biometric Login** to ON pushes a full-screen biometric prompt (route `/biometric`). The OS fingerprint / face-unlock sheet appears; if it passes, the screen pops with `true` and `user_settings.biometric_enabled` flips to true. If the user cancels or fails, the screen pops with `false` and the toggle snaps back off — **no row write happens**. Turning the toggle OFF persists directly without a re-prompt (downgrades don't need a fresh biometric check).

**Important.** This is an **enrollment gate**, not a sign-in mechanism. Today, having `biometric_enabled = true` simply records the user's preference; the existing email/OTP login flow has not changed. Wiring biometric auth into actual sign-in is a separate piece of work.

**Data model.** No new table. Reuses `user_settings.biometric_enabled` from §6.1.

**Ops actions.**
- Force-disable an investor's biometric flag (e.g. they lost the device):
  ```sql
  UPDATE public.user_settings SET biometric_enabled = false
  WHERE user_id = (SELECT id FROM public.investors WHERE email = 'jane@example.com');
  ```
- This does not log the user out — it only affects what the Security screen shows on next entry.

**Migration.** None of its own; piggybacks on `026`.

---

### 6.3 Investor self-onboarding (InitialSetupScreen)

**User journey.** From the launch screen → **Get Started** → 3-step wizard at `/setup`:

1. **Personal Details** — full name, email (pre-filled from auth user), date of birth (`DD-MM-YYYY`).
2. **Identity Verification** — PAN (auto-uppercased, must match `^[A-Z]{5}[0-9]{4}[A-Z]$`) and Aadhaar (exactly 12 digits).
3. **Bank Account** — bank name, IFSC (`^[A-Z]{4}0[A-Z0-9]{6}$`), account number (9–18 digits), holder name.

Each field validates inline. **Submit for Verification** writes the row and routes to Home with a "KYC pending" toast.

**Privacy.** Raw PAN, Aadhaar, and account numbers **never leave the device**. The app masks them client-side before writing — `pan_masked` becomes `ABCDE****F`, `aadhaar_masked` becomes `XXXX-XXXX-1234`, `bank_account_masked` becomes `XXXXX1234`. This matches the existing `bank_change_request` pattern. If ops needs the full numbers, they have to be collected out-of-band (existing Zoho-side flow).

**Data model.** Migration `027_investors_self_onboard.sql` modifies `public.investors`:

| Change | Why |
|---|---|
| `arl_id` is now nullable | Self-onboarded rows have no Zoho contact ID until staff assigns one. Existing Zoho-synced rows keep their `arl_id` unchanged. |
| New policy `investors: insert own row` | `WITH CHECK (id = auth.uid())` — investor can create their own row. |
| New policy `investors: update own row` | `USING/CHECK (id = auth.uid())` — investor can update their own row. |
| `GRANT INSERT, UPDATE ON public.investors TO authenticated` | Previously was SELECT only. |

The wizard does a single `upsert` keyed on `id = auth.uid()`. New rows get `kyc_status = 'pending'`.

**Ops actions.**
- Find investors waiting for KYC review:
  ```sql
  SELECT id, name, email, pan_masked, aadhaar_masked, bank_name, bank_ifsc, bank_account_masked
  FROM public.investors
  WHERE kyc_status = 'pending' AND arl_id IS NULL
  ORDER BY updated_at DESC;
  ```
- After verifying KYC out-of-band, assign an `arl_id` and flip status:
  ```sql
  UPDATE public.investors
  SET arl_id = 'ARL-2026-NNNN', kyc_status = 'verified'
  WHERE id = '<uuid>';
  ```
- The masked values are app-display only. If you need the full PAN / Aadhaar / account, contact the investor — we don't store them.

**Migration.** `027` — 2026-05-12. Rollback drops the two policies, revokes grants, and re-adds `NOT NULL` to `arl_id`.

---

### 6.4 Consultation requests (ExploreScreen)

**User journey.** Investor opens **Explore** tab → browses marketplace listings → opens one → picks a unit count via slider or custom input → taps **Request Consultation**. The button shows an inline spinner while the request is being saved, then a toast confirms. Tapping again within 24 hours surfaces a "we already have your request" toast instead of creating a duplicate.

**Dedup.** The 24-hour check is **client-side** — the repo runs a SELECT for the user's `new` requests on this project in the last 24h before inserting. The window is intentionally short so an investor *can* re-file a fresh consultation 24h later without admin intervention. There is no DB unique constraint.

**Data model.** Migration `028_consultation_requests.sql`:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | |
| `user_id` | uuid → `auth.users` | |
| `project_id` | uuid → `public.projects` | |
| `units_requested` | int nullable | |
| `message` | text nullable | not currently surfaced in the app, but allowed in the schema |
| `status` | text default `'new'` | check (`new` \| `contacted` \| `closed`) |
| `created_at` | timestamptz | |

Indexes: `(user_id, created_at DESC)`, `(project_id, status, created_at DESC)`. RLS: `select own` + `insert own` (both `user_id = auth.uid()`). `GRANT SELECT, INSERT TO authenticated`. Staff bypass via service_role.

**Status lifecycle.** `new` (just submitted) → `contacted` (ops reached out) → `closed` (resolved one way or the other). Today ops moves rows by hand in Studio.

**Ops actions.**
- Daily triage — open requests sorted by oldest:
  ```sql
  SELECT cr.id, cr.created_at, cr.units_requested, p.name AS project,
         i.name AS investor, i.email, i.phone
  FROM public.consultation_requests cr
  JOIN public.projects p ON p.id = cr.project_id
  JOIN public.investors i ON i.id = cr.user_id
  WHERE cr.status = 'new'
  ORDER BY cr.created_at ASC;
  ```
- After calling the investor, mark contacted:
  ```sql
  UPDATE public.consultation_requests SET status = 'contacted' WHERE id = '<uuid>';
  ```
- Close once resolved (`status = 'closed'`). Closed rows are not re-surfaced by the in-app dedup check, so the investor can submit a fresh request later.

**Migration.** `028` — 2026-05-12. Rollback: `DROP TABLE public.consultation_requests;`.

---

### 6.5 Exit requests (ExitScreen)

**User journey.** From Profile → **Project Exit** → `/exit`. The screen shows investment date, lock-in end date (`investment_date + 5 years`), and an eligibility chip. If the lock-in has passed, **Request Exit** is enabled; tapping it opens a small reason dialog (optional text, up to 500 chars) before submit. After submit, the screen flips to a **"Exit request pending review"** card with the submission date — the CTA is no longer shown until ops moves the status off `pending`.

**Race-safe dedup.** Unlike consultation requests, exits use a **DB-level** partial unique index: `uniq_exit_requests_pending_unit ON exit_requests (investor_unit_id) WHERE status = 'pending'`. Two simultaneous taps cannot both create pending rows for the same allocation. The client catches `PostgrestException` with SQLSTATE `23505` and surfaces the existing pending row — UX wise the second tap looks like "already submitted" rather than "error".

**Why the FK is `investor_unit_id`, not `project_id`.** Investors hold allocations (`investor_units` rows), not projects. One project can have multiple allocations to the same investor; each can be exited independently in principle. Today the screen targets the **earliest** `investor_units` row for the user — sufficient for the current single-allocation case, easy to extend later.

**Data model.** Migration `029_exit_requests.sql`:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | |
| `investor_unit_id` | uuid → `public.investor_units` | the specific allocation under exit |
| `user_id` | uuid → `auth.users` | |
| `reason` | text nullable | free-form from the reason dialog |
| `status` | text default `'pending'` | check (`pending` \| `approved` \| `rejected` \| `settled`) |
| `created_at` | timestamptz | |
| `resolved_at` | timestamptz nullable | ops sets when status leaves `pending` |

Indexes: `(user_id, created_at DESC)`, **plus** the partial unique index above. RLS: `select own` + `insert own`. `GRANT SELECT, INSERT TO authenticated`. UPDATE is staff-only via service_role.

**Status lifecycle.** `pending` → either `approved` (ops agrees to exit, valuation in progress) → `settled` (payout cleared), OR `rejected` (denied with reason in `resolved_at` context).

**Ops actions.**
- Pending queue, oldest first:
  ```sql
  SELECT er.id, er.created_at, er.reason,
         i.name AS investor, i.email, i.phone,
         p.name AS project, iu.investment_date, iu.issued_units, iu.capital_invested
  FROM public.exit_requests er
  JOIN public.investor_units iu ON iu.id = er.investor_unit_id
  JOIN public.investors i ON i.id = er.user_id
  JOIN public.projects p ON p.id = iu.project_id
  WHERE er.status = 'pending'
  ORDER BY er.created_at ASC;
  ```
- Approve (valuation step starts out-of-band):
  ```sql
  UPDATE public.exit_requests SET status = 'approved', resolved_at = now() WHERE id = '<uuid>';
  ```
- Reject (after a conversation that confirms the investor wants to hold):
  ```sql
  UPDATE public.exit_requests SET status = 'rejected', resolved_at = now() WHERE id = '<uuid>';
  ```
  A rejected row stops blocking the partial unique index, so the investor can file fresh if circumstances change.
- Once settlement clears: `status = 'settled', resolved_at = now()`.

**Migration.** `029` — 2026-05-12. Rollback: `DROP TABLE public.exit_requests;`.

---

## Part 7 — Document Tiering (Common / Project / Investor)

Migration `032` adds a `visibility` column to `public.documents` so a single uploaded document can be scoped to one of three tiers:

| Tier       | Who sees it                                                        | `investor_id` | `project_id` |
|------------|--------------------------------------------------------------------|---------------|--------------|
| `common`   | Every authenticated investor                                       | NULL          | NULL         |
| `project`  | Investors who hold units in `project_id`                           | NULL          | required     |
| `investor` | The investor identified by `investor_id` (legacy default)          | required      | optional     |

The CHECK constraint `documents_tier_columns_check` enforces those nullability rules — bad inserts are rejected at write time, so the app can't end up with a "common doc" that secretly carries an `investor_id`. RLS policy `documents: tiered read` reads them per the table above; storage RLS mirrors the same shape on bucket paths.

### How to upload a common document

Common documents live at the top of `arl-documents/common/`. Anyone authenticated can read them once they're indexed.

1. Open **Supabase Studio → Storage → arl-documents**. Navigate into the `common/` folder (create it on first use).
2. Upload your file. Note the final path — e.g. `common/sample-agreement-template-v3.pdf`.
3. Open **SQL Editor** and insert a documents row pointing at that path:
   ```sql
   INSERT INTO public.documents
     (name, doc_type, visibility, storage_path, file_size_kb, uploaded_at)
   VALUES
     ('Sample Agreement Template v3', 'agreement', 'common',
      'common/sample-agreement-template-v3.pdf', 142, now());
   ```
4. Open the Flutter app as any investor — the doc appears under the **Common** accordion on the Documents screen.

### How to upload a project document

Project documents live at `arl-documents/project/{project_id}/...`. Only investors with a row in `investor_units` for that `project_id` see them.

1. Look up the project id: `SELECT id, name FROM public.projects WHERE name ILIKE '%pineapple%';`
2. Upload the file to **Storage → arl-documents → project → <project_id>** (create both folders on first use).
3. Insert the row, providing both `visibility='project'` and `project_id` (and leaving `investor_id` NULL):
   ```sql
   INSERT INTO public.documents
     (name, doc_type, visibility, project_id, storage_path, file_size_kb, uploaded_at)
   VALUES
     ('Pineapple LLP Q4 Land Survey', 'other', 'project',
      '<project_id>',
      'project/<project_id>/pineapple-llp-q4-survey.pdf',
      512, now());
   ```
4. Verify visibility: query as a unit-holder via SQL Editor with role `authenticated` and the investor's `auth.uid()` (or just open the app as them).

### How to upload an investor document

The original tier — used for personal contracts, signed KYC packets, payout statements. Path lives at `arl-documents/investor/{auth_user_id}/...`.

1. Look up the investor: `SELECT id, name, email FROM public.investors WHERE email = 'investor@example.com';`. The `id` IS the `auth.users.id`.
2. Upload to **Storage → arl-documents → investor → <id>**.
3. Insert pointing to that path with `visibility='investor'` and `investor_id` filled (default works, but explicit is fine):
   ```sql
   INSERT INTO public.documents
     (name, doc_type, visibility, investor_id, storage_path, file_size_kb, uploaded_at)
   VALUES
     ('Pineapple LLP — Signed Agreement', 'agreement', 'investor',
      '<investor_id>',
      'investor/<investor_id>/pineapple-llp-signed-agreement.pdf',
      284, now());
   ```
4. As that investor, refresh the Documents screen — the row appears under **My Documents**.

### Gotchas

- `visibility = 'common'` rows MUST keep `investor_id = NULL` and `project_id = NULL`. The CHECK constraint will reject anything else with `documents_tier_columns_check`.
- Direct `INSERT` from the app is restricted to `visibility='investor'` with `investor_id = auth.uid()` (RLS policy `documents: insert own investor doc`). Common + project tiers MUST go via Studio (service_role) or an Edge Function.
- Storage and DB row are two writes — if you uploaded the file but forgot the DB insert, the app won't show it; if you inserted the row but didn't upload, the signed URL fetch fails silently and the row renders with a broken open-button. Always do BOTH.
- Soft-deleting a project (Zoho LLP delete trigger) leaves project-tier documents with `project_id = NULL` (FK `ON DELETE SET NULL`). They go silent in the app — RLS filters `project_id IN (...)` so a NULL project_id matches nothing.

**Migration.** `032` + `033` — 2026-05-13. Rollback (destructive — only on dev):
```sql
DROP POLICY IF EXISTS "documents: tiered read" ON public.documents;
DROP POLICY IF EXISTS "documents: insert own investor doc" ON public.documents;
ALTER TABLE public.documents DROP CONSTRAINT IF EXISTS documents_tier_columns_check;
ALTER TABLE public.documents DROP COLUMN IF EXISTS visibility;
ALTER TABLE public.documents DROP COLUMN IF EXISTS project_id;
ALTER TABLE public.documents ALTER COLUMN investor_id SET NOT NULL;
-- and restore the legacy storage policy
```

---

## Part 8 — Soft-Delete Sync from Zoho CRM

Investors, LLPs, and Projects now carry a `deleted_at TIMESTAMPTZ` column. When ops deletes the corresponding record in Zoho CRM, the workflow fires the `zoho-crm-webhook` with `operation=delete` and the row's `deleted_at` is stamped with `now()`. RLS hides soft-deleted rows from the app; FK chains (investor_units → projects → payouts → documents → exit_requests) keep their parents around for audit.

**Behaviour**
- Contact delete in Zoho → `investors.deleted_at = now()` + the `auth.users` row is banned for 100 years (effectively indefinite). The investor can't sign back in. Refresh tokens stop exchanging within minutes.
- LLP delete in Zoho → `llps.deleted_at = now()` cascades to every active project under that LLP (`projects.deleted_at = now() WHERE llp_id IN (...)`). Project-tier documents are not deleted; they point at a soft-deleted project and silently disappear from app reads (RLS).
- App layer also passes `.isFilter('deleted_at', null)` explicitly on investor + project queries — defense in depth against an accidental RLS regression.

**Restoring a soft-deleted row** (rare — usually a Zoho operator mistake):
```sql
-- Restore an investor
UPDATE public.investors SET deleted_at = NULL WHERE arl_id = 'ARL-00142';
-- Unban their auth.users row
SELECT auth.admin.update_user_by_id('<auth_user_id>', '{"ban_duration":"none"}'::jsonb);
-- Restore an LLP and its projects
UPDATE public.llps     SET deleted_at = NULL WHERE id = '<llp_id>';
UPDATE public.projects SET deleted_at = NULL WHERE llp_id = '<llp_id>';
```

**Migration.** `030` + `031` — 2026-05-13. Rollback: `ALTER TABLE ... DROP COLUMN deleted_at` on each of investors/llps/projects (also drops indexes via cascade), and restore the prior policies from `009` / `018` / `021` / `027`.

---

## Part 9 — In-App Notification Triggers

Four state transitions now produce a notification row automatically via DB triggers — no Edge Function or app-side post-write needed. Functions are `SECURITY DEFINER` with `SET search_path = public, pg_temp` so they fire regardless of who issued the UPDATE.

| Source table              | Transition                                          | Notification type | Body                                                |
|---------------------------|-----------------------------------------------------|-------------------|-----------------------------------------------------|
| `investors`               | `kyc_status` pending → verified                     | `kyc`             | "Your KYC has been verified. Tap to view."          |
| `investors`               | `kyc_status` pending → rejected                     | `kyc`             | "Your KYC has been rejected. Please re-submit."     |
| `exit_requests`           | `status` pending → approved/rejected/settled        | `exit`            | Status-specific copy                                |
| `ticket_messages`         | INSERT WHERE `sender_type='staff'`                  | `ticket`          | "New reply on ticket #<short_id>."                  |
| `bank_change_requests`    | `status` pending → approved/rejected                | `bank_change`     | Status-specific copy + verifier notes if rejected   |

**Notes**
- `notifications.type` CHECK constraint was expanded to add `kyc`, `exit`, `bank_change`. Existing values (`payout`, `photo`, `ticket`, `reminder`, `milestone`) are preserved.
- All triggers use `IS DISTINCT FROM OLD.<col>` so no-op writes do not produce ghost notifications.
- The ticket-reply trigger silently no-ops when the parent ticket has been deleted between the message INSERT and trigger fire.

**To check a fire** (after, say, you mark a KYC verified in Studio):
```sql
SELECT id, type, title, body, created_at
FROM public.notifications
WHERE investor_id = '<auth_user_id>'
ORDER BY created_at DESC
LIMIT 5;
```

**Migration.** `034` — 2026-05-13. Rollback:
```sql
DROP TRIGGER  IF EXISTS trg_notify_investor_kyc_status_change   ON public.investors;
DROP TRIGGER  IF EXISTS trg_notify_exit_request_status_change   ON public.exit_requests;
DROP TRIGGER  IF EXISTS trg_notify_ticket_reply                 ON public.ticket_messages;
DROP TRIGGER  IF EXISTS trg_notify_bank_change_status_change    ON public.bank_change_requests;
DROP FUNCTION IF EXISTS public.notify_investor_kyc_status_change();
DROP FUNCTION IF EXISTS public.notify_exit_request_status_change();
DROP FUNCTION IF EXISTS public.notify_ticket_reply();
DROP FUNCTION IF EXISTS public.notify_bank_change_status_change();
-- Optional: restore tighter notifications.type CHECK
```

---

---

## Part 10 — Topic-Specific Deep Dives

This guide is the master index. Some workflows are deep enough that they live in their own files under `docs/ops/`. Read those when you need the step-by-step, with copy-pasteable SQL and screen-by-screen walkthroughs. Each was written 2026-05-15 against the live database (`oynfhdqizebvgmaoiuax`) using the test investor `ofclash98@gmail.com` (`27d3735e-470d-47a5-a413-9ae502194d3d`); the SQL is real and the recipes were executed end-to-end.

### 10.1 — Support tickets

**Read:** `docs/ops/tickets.md` (709 lines)

What it covers: schema of `support_tickets` + `ticket_messages`, RLS, the `create-ticket` and `reply-ticket` edge functions, the `trg_notify_ticket_reply` trigger from migration 034, and the four Flutter screens under `lib/features/support/`. Includes recipes T-1 through T-6: reply from ops, close/re-open, look up by investor, find aging tickets, and the FG-01 stopgap for initiating a ticket addressed to an investor (the trigger fires automatically because `sender_type='staff'` is the gate).

When to consult: any ops touching `support_tickets`, `ticket_messages`, or wanting to know what the bell badge counts.

### 10.2 — Marketplace project lifecycle

**Read:** `docs/ops/marketplace.md` (816 lines)

What it covers: how a project flows from Zoho `LLP_Creation_Module` → webhook → `llps` + `projects` → Explore screen card. Documents the exact Dart filter predicates for "All" / "Open for Reservation" / "Coming Soon" tabs (post commit `2d3ddae`). Includes recipes M-1 through M-6 covering listing, status transitions, marketplace card metadata, and sunset. Auto-balance for `units_available` was investigated — the recommended fix would race the Zoho webhook, so it is documented as a future planned change and NOT shipped. Manual reconcile recipe M-5 is the current workaround.

When to consult: adding a new project, debugging "why isn't this project showing up in Explore", or reconciling a drift between `projects.units_issued` and `sum(investor_units.issued_units)`.

### 10.3 — Documents tiering

**Read:** `docs/ops/documents.md` (563 lines)

What it covers: the 3-tier document model from migrations 032 + 033 — `common`, `project`, `investor`. Storage bucket conventions for `arl-documents`, the `documents_tier_columns_check` invariant, and the RLS predicates for both `public.documents` and `storage.objects`. Includes recipes D-1 through D-7: upload common/project/investor docs, replace, delete, bulk upload, and audit visibility. Flagged P1: the four existing seed rows have `storage_path` values prefixed with `documents/` but the storage RLS predicate matches on first-folder = `common`/`project`/`investor`. Bucket is empty so the bug is latent — engineering call needed before shipping.

When to consult: any time ops uploads a PDF for investors to view, or you need to debug "why can't this investor see this document".

### 10.4 — Investor profile management

**Read:** `docs/ops/investor_profile.md` (1012 lines)

What it covers: the full ops checklist for editing any aspect of an investor's profile — personal info, KYC, sensitive identity fields (PAN/Aadhaar/DOB/bank), project assignments, payouts, exit requests, bank change requests, auth-level controls, PIN reset, and account deletion. Each follows the WHAT / WHO / WHERE / WHEN / NOTIFICATION / SQL / ROLLBACK template. Live-tested KYC + exit-request + bank-change-request state transitions against migration 034 triggers. Master quick-reference table at the end.

When to consult: any change you make to an `investors` row, or any time you're processing a request the investor submitted (exit, bank change, KYC re-submission).

### Defect roll-up surfaced during this consolidation pass

These are summarised here so the master guide carries the breadcrumb. Full reproduction steps live in each deep-dive doc.

| Tag           | Severity | Topic        | Headline                                                                                                              |
|---------------|----------|--------------|-----------------------------------------------------------------------------------------------------------------------|
| DEF-MKT-01    | P1       | Marketplace  | `Sample Test LLP` has `units_available = -30`. No CHECK constraint guards against `units_issued > total_units`.       |
| DOC-RLS-PATH  | P1       | Documents    | Seed `documents.storage_path` values prefixed `documents/` but storage RLS reads folder level 1 — paths can't co-exist. Bucket empty, latent. |
| D-1           | P2       | Tickets      | Status flips don't push to investor UI without a manual refresh. No Realtime subscription on ticket providers.        |
| D-2           | P2       | Tickets      | New-ticket submit button overlaps bottom nav; first tap can land on `/documents`.                                     |
| DEF-MKT-02    | P2       | Marketplace  | 5 projects drift between `projects.units_issued` and `sum(investor_units.issued_units)`. M-5 recipe is the workaround.|
| DEF-MKT-03    | P2       | Marketplace  | `projects.units_issued` is NULL on two UAT rows; column should default to 0.                                          |
| DEF-OPS-1     | P2       | Profile      | Webhook never pushes Zoho `Contacts.Email` to `auth.users.email`. Sign-in email can drift from profile email.         |
| DEF-OPS-2     | P2       | Profile      | Exit-request `approved → settled` does not fire a notification — trigger gates on `OLD.status='pending'`.             |
| DEF-OPS-3     | P2       | Profile      | Webhook does not pull `Contacts.Date_of_Birth` or `Contacts.Aadhaar_Number`. Only the self-onboard path writes those. |
| DEF-OPS-4     | P2       | Profile      | Webhook does not handle `LLP_UnitAllocation_Module` delete operation — cancellations leave Supabase rows active.      |
| DEF-OPS-5     | P2       | Profile      | `kyc_resubmissions` status changes do not fire a notification.                                                        |
| D-3 / D-4 / D-5 | P3     | Tickets      | UUID display cosmetic; notification body wording for ops-initiated tickets; `bank_change`/`exit_request` not selectable as ticket categories. |
| DEF-MKT-04/05 | P3       | Marketplace  | `marketplace_sort_order` mostly 0 (no convention); cosmetic `Darft` typo in Zoho status picklist (ignored by allow-list). |
| DEF-OPS-6/7   | P3       | Profile      | `investors.address_line2` is dead column; `kyc_status='in_progress'` does not fire a notification.                    |

### FG-01 status

Still open. Ops can now use **Recipe T-6** in `docs/ops/tickets.md` (single CTE, INSERT support_tickets + INSERT ticket_messages with `sender_type='staff'`) to initiate a ticket addressed to an investor. The migration 034 trigger fires the bell automatically. This is the recommended stopgap until an ops admin UI exists.

---

**End of guide.** If you've followed something here and it didn't work, OR you have a use case not covered, file an issue + ping engineering. This document gets out of date — verify against the actual system if in doubt.

Cross-references:
- `docs/data_flow_guide.md` — architecture reference (for engineers).
- `docs/debug_runbook.md` — failure playbook (for engineers at 2am).
- `docs/testing/runs/` — UAT logs from past test runs.
- `docs/ops/tickets.md` — support ticket lifecycle deep-dive (Part 10.1).
- `docs/ops/marketplace.md` — marketplace project lifecycle deep-dive (Part 10.2).
- `docs/ops/documents.md` — documents tiering deep-dive (Part 10.3).
- `docs/ops/investor_profile.md` — investor profile management deep-dive (Part 10.4).
