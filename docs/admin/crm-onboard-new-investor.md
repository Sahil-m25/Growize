# Admin Guide: Onboard a New Investor in Zoho CRM

**Audience:** ARL ops team  
**Purpose:** Create a new investor Contact and allocate units to a project — end to end — so the investor appears correctly in the Growize app.

> **Why this matters:** The Growize app reads all investor and allocation data from Supabase, which is populated by the Zoho CRM webhook. If any required CRM field is left blank, the app will show wrong numbers (zero returns, zero portfolio %, duplicate unit counts). Follow every step exactly.

---

## Part 1 — Create the Contact

### Step 1: Open Contacts module
In the CRM left sidebar, click **Contacts**.

### Step 2: New Contact
Click the **+ New Contact** button (top-right).

### Step 3: Fill required fields

| CRM Field | What to enter | Notes |
|---|---|---|
| **First Name / Last Name** | Investor's full legal name | Will appear in the app header |
| **Email** | Investor's email address | Used for Supabase auth invite — must be exact |
| **Phone** | Mobile number | Shown on profile screen |
| **Salutation** | Mr. / Ms. / Dr. | Displayed in greeting |
| **Date of Birth** | DD/MM/YYYY | Used for KYC screen |
| **PAN Number** | As per KYC docs | Stored masked — last 4 chars only |
| **ARL ID** | Assign next sequential ARL-XXXX | e.g. ARL-0042 |

> Leave bank fields blank for now — investor fills them via the app's bank-change flow after onboarding.

### Step 4: Save
Click **Save**. Note the **Contact ID** from the URL bar (e.g. `1169101000001234567`).

---

## Part 2 — Allocate Units (LLP_UnitAllocation_Module)

### Step 5: Open Unit Allocation module
In the CRM sidebar, click **LLP Unit Allocation** (or search for it under modules).

### Step 6: New Allocation record
Click **+ New**.

### Step 7: Link to Contact and LLP
| CRM Field | What to enter |
|---|---|
| **Contact** | Search and select the Contact you just created |
| **LLP** | Select the target LLP (e.g. "Eka LLP") |

### Step 8: Fill allocation fields — ALL fields are required

> **CRITICAL:** Every field in the table below must be filled. Leaving any field blank will cause the app to show wrong data (zero portfolio value, zero returns, 0% portfolio allocation).

| CRM Field | What to enter | Maps to Supabase |
|---|---|---|
| **Issued Units** | Number of units allocated (e.g. `1`) | `issued_units` |
| **Capital Invested** | Total capital committed in INR (e.g. `2500000`) | `capital_invested` |
| **Total Amount Receivable** | Expected total return amount | `total_amount_receivable` |
| **Total Amount Received / Total Amount Paid** | Amount actually received from investor so far | `total_amount_received` |
| **Annual Rental Yield** | Yield % (e.g. `18`) | `annual_yield_pct` |
| **Allocation Status** | Set to `Issued` | `allocation_status` |
| **Investment Date** | Date the investment was formalised | `investment_date` |

> **Capital Invested vs Total Amount Paid:** These are different fields. "Capital Invested" is the committed amount (full ticket size). "Total Amount Paid" is how much the investor has actually transferred. At the time of allocation, if the full amount is received, both should be the same number. Do not leave "Capital Invested" blank even if "Total Amount Paid" is already filled — leaving it blank results in `₹0` showing as the portfolio value.

### Step 9: Save the allocation record

---

## Part 3 — Invite investor to the app

### Step 10: Send Supabase auth invite
Go to **Supabase Studio → Authentication → Users → Invite user**.
Enter the same email address used in Step 3. The investor receives a magic link to set up their account.

> The Supabase `investors` row is created automatically when the CRM webhook fires (triggered on save in Step 4 / Step 9). The auth invite links the auth user to that investor row.

---

## Part 4 — Verify data synced correctly

After saving the allocation in the CRM, allow 1–2 minutes for the webhook to fire. Then verify:

### Step 11: Check Supabase
Go to **Supabase Studio → Table Editor → investor_units**.

Filter by the investor's email (via join on `investors`). You should see **exactly one active row** (`deleted_at = null`) with:
- `issued_units` = what you entered
- `capital_invested` = what you entered (must not be 0)
- `total_amount_received` = what you entered
- `annual_yield_pct` = what you entered

### Step 12: Check the webhook log
In **Table Editor → webhook_log**, filter `source = zoho_crm`. The most recent entry for this investor should show `status = processed`.

### Step 13: Check the app
Ask the investor to open the app (or use a test account). Verify:
- **Dashboard** → "Total Portfolio Value" = correct invested amount
- **Dashboard** → "Active Units" = correct unit count
- **Projects** → Select project → "% of portfolio" = 100% (if only project)
- **Projects** → "Total Invested" = correct amount
- **Projects** → "Payouts to Date" = ₹0 (correct — no payouts yet)

---

## Common Mistakes to Avoid

| Mistake | What goes wrong in the app |
|---|---|
| Leaving "Capital Invested" blank | Portfolio value shows ₹0; "% of portfolio" shows 0% |
| Creating two allocation records for the same investor + LLP without deleting the old one | Unit count doubles; portfolio value doubles |
| Mistyping the investor email between CRM and Supabase invite | Auth invite won't link to their investor row; they can't see their data |
| Setting "Allocation Status" to anything other than "Issued" | Record may not appear in the app (depending on RLS filter) |

---

## If something looks wrong after sync

1. Check `webhook_log` in Supabase Studio for `status = failed` entries.
2. Confirm the allocation record in CRM has all fields filled (especially **Capital Invested**).
3. If a duplicate `investor_units` row was accidentally created, soft-delete the stale one: set `deleted_at = now()` via Supabase Studio Table Editor on the old row. Do **not** hard-delete rows.
4. Ping the engineering team with the `zoho_allocation_id` of the problem record.
