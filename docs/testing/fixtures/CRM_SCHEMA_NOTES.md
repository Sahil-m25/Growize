# Zoho CRM Schema — Live Reference

**Created:** 2026-05-05
**Source of truth:** `getLayouts` (active layout) for each module — NOT `getFields` metadata.
**Why this file exists:** `getFields` returns a superset (every field that ever existed in metadata, including stale/inactive ones). The **active layout** is what actually accepts writes and returns reads. Always cross-check against the active layout before writing test fixtures.

---

## Modules in scope

| Purpose | API name | Notes |
|---|---|---|
| LLP master (entity that holds one project + units) | `LLP_Creation_Module` | Use this. Real records: "Pineapple Enterprises", "Xiaomi LLP". |
| Per-investor allocation (incl. payment ledger) | `LLP_UnitAllocation_Module` | Active layout name "LLP Unit Allocation Information". |
| Investor | `Contacts` | Standard module. |
| Deal (optional, lookup target) | `Deals` | Standard module. |
| **Deprecated, do NOT use** | `LLP_Unit_Allocation` (no underscore between "Unit" and "Allocation") | 1 stray record, abandoned schema. |

---

## `LLP_Creation_Module` — LLP/Project master

**Required:** `Name` (text)

**Active fields used by app:**

| API name | Type | Notes |
|---|---|---|
| `Name` | text (required) | LLP/project name. Append `-demo` for fixtures. |
| `Total_Units` | integer | Total units in the project |
| `Pet_Unit_Price` | currency | Per-unit price (yes, the API name has this typo) |
| `LLP_Status` | picklist | Values: `Darft`, `Open for Reservation`, `Open for Issuance`, `Fully Subscribed / Closed`, `Active`, `On Hold` |
| `Tier` | picklist | Values: `5 CR`, `1 CR`, `50 L`, `25 L`, `10 L` |
| `Annual_Rental_Yield` | picklist | Values: `20%`, `23%`, `25%`, `27%`, `28%`, `29%`, `30%` |
| `LLP_Owner` | text | |
| `Total_Project_Cost` | currency | |
| `Total_Ticket_Size` | currency | |
| `Token_Amount_Received` | currency | |
| `Receivable_Ticket_Amount` | currency | |
| `Issued_Ticket_Amount_Received` | currency | "Received Ticket Amount" |
| `Units_Issued` | integer | |
| `Units_Reserved` | integer | |
| `Units_Available_to_Issue` | integer | |
| `Units_Available_to_Reserve` | integer | |
| `Insurance_Provider`, `Insurance_Policy_No`, `Insured_Amount`, `Insurance_expiry_date` | various | Insurance info |
| `GST`, `PAN`, `Incorporation_No` | text | Legal identifiers |
| `LLP_Owner`, `No_of_partners`, `Acreage_Acres`, `Launch_Year` | various | |
| `SPOC_1_Full_Name`, `SPOC_1_Contact_No`, `SPOC_2_*` | text/phone | Contact persons |
| `Address_Line_1*`, `Address_Line_2*` | various | Full address blocks (city, state, country, lat/long, zip) |

**Fields that exist in `getFields` metadata but NOT on active layout — DO NOT WRITE:**

(none confirmed yet — most metadata fields in this module appear on the layout)

---

## `LLP_UnitAllocation_Module` — per-investor allocation

**Active layout:** "LLP Unit Allocation Information" (id `1169101000000755152`)

**Required fields (CANNOT skip when creating):**

- `Name` (text)
- `Customer` (lookup → Contacts)
- `Customer_Email` (email)
- `LLP` (lookup → `LLP_Creation_Module`)
- `Investment_Date` (date)
- `Reserved_Units` (integer)
- `Token_Advance_Amount` (currency)
- `Issued_Units` (integer)

**Lookup fields — proper API names and targets:**

| Display | API name | Target module |
|---|---|---|
| Customer | `Customer` | Contacts |
| Deal | `Deal` (NOT `Deal_Name`) | Deals |
| Customer List (LLP) | `LLP` (NOT `LLP_Lookup`) | LLP_Creation_Module |

**All other on-layout fields:**

| API name | Type | Notes |
|---|---|---|
| `Customer_Status` | picklist | Values: `Active`, `Exit Requested`, `Exit in progress`, `Exited Partially`, `Exited Fully`. **This holds the exit state per allocation** (not per LLP). |
| `Allocation_Status` | picklist | Values: `Reserved`, `Issued`, `Cancelled` |
| `Total_LLP_Units` | integer | Snapshot of LLP-level total (de-normalized) |
| `Unit_Price` | currency | Per-unit price |
| `Units_Available` | integer | |
| `Total_Amount_Receivable` | currency | Outstanding from this investor |
| `Total_Amount_Received` | currency | Sum of payments received from this investor |
| `Capital_Invested` | currency | |
| `Capital_Returns` | currency | |
| `Capital_Outstanding` | currency | |
| `Annual_Rental_Yield` | picklist | (same values as on LLP) |
| `Next_Payout` | date | |

**Banking Transaction section** — payment ledger embedded on the allocation:

- `Amount_1`..`Amount_10` (currency) — each is one payment installment.
- `UTR`, `UTR_2`..`UTR_10` (text) — bank UTR per installment.
- `Date_1`..`Date_10` (date) — payment date per installment.

> **Payment state derivation:** the app derives Pending / Partial / Paid by comparing how many of the 10 banking slots are populated, plus `Total_Amount_Received` vs `Token_Advance_Amount + Total_Amount_Receivable`. There is no `Payment_Status` picklist on the live layout.

**Fields that exist in `getFields` metadata but NOT on active layout — DO NOT WRITE:**

- `Deal_Name` (use `Deal` instead — points to same Deals module)
- `LLP_Lookup` (use `LLP` instead — points to LLP_Creation_Module)
- `Payment_Status` (no such picklist on live layout — use banking ledger + Allocation_Status instead)
- `Exit_Status` (use `Customer_Status` instead)
- `Committed_Units` (use `Reserved_Units` instead)
- `Committed_Amount` (no equivalent — use `Token_Advance_Amount` + `Total_Amount_Receivable` to represent committed amount)
- `Issued_Amount` (use `Total_Amount_Received` instead)
- `Agreement_Signed`, `Reserved_Amt_Receivable`, `Ticket_Size_Snapshot` (not on active layout)

---

## Allocation → LLP relationship

**Confirmed:** The allocation record's `LLP` lookup field points at `LLP_Creation_Module`. So the data model is:

```
LLP_Creation_Module (one record per LLP/project)
        ▲
        │ LLP lookup
        │
LLP_UnitAllocation_Module (one record per investor per LLP)
        │
        ├── Customer → Contacts
        ├── Deal     → Deals (optional)
        └── Banking Transaction (Amount_1..10 / UTR / Date)
```

Per-investor exit state lives on the allocation (`Customer_Status` field).
Per-investor payment state is **derived** from the banking transaction ledger + amount fields, not stored as a picklist.

---

## Lessons that produced this file

1. **`getFields` returns metadata-superset, not active layout.** Always confirm fields appear on the active layout via `getLayouts` before writing.
2. **Zoho silently drops unknown fields on create.** No error, no warning — the record is created with only the fields it recognized. We discovered this by reading back the canary record and finding it empty.
3. **API names sometimes differ from display labels.** `Pet_Unit_Price` is "Per Unit Price". `LLP` lookup field has display label "Customer  List". Always trust the API name from `getLayouts.sections[].fields[].api_name`.
4. **Picklists with display values containing `-None-` cannot be queried via COQL.** Use `getRecords` with explicit `fields=` parameter for those.
5. **Schema dumps from `getFields` exceed the response window for some modules.** Save to file and parse offline — never trust a partial read.

---

## Quick reference — verified write-safe fields

### LLP_Creation_Module (LLP master)
```
Name, Total_Units, Pet_Unit_Price, LLP_Status, Tier,
Annual_Rental_Yield, LLP_Owner, Total_Project_Cost,
Total_Ticket_Size, Receivable_Ticket_Amount,
Token_Amount_Received, Issued_Ticket_Amount_Received,
Units_Issued, Units_Reserved, Units_Available_to_Issue,
Units_Available_to_Reserve, GST, PAN, Incorporation_No,
No_of_partners, Acreage_Acres, Launch_Year,
Insurance_Provider, Insurance_Policy_No, Insured_Amount,
SPOC_1_Full_Name, SPOC_1_Contact_No,
SPOC_2_Full_Name, SPOC_2_Contact_No
```

### LLP_UnitAllocation_Module (allocation)
```
Name, Customer (lookup), Customer_Email, Deal (lookup, optional),
LLP (lookup, required), Investment_Date,
Reserved_Units, Issued_Units, Token_Advance_Amount,
Total_LLP_Units, Unit_Price, Units_Available,
Total_Amount_Receivable, Total_Amount_Received,
Capital_Invested, Capital_Returns, Capital_Outstanding,
Annual_Rental_Yield, Allocation_Status, Customer_Status,
Next_Payout,
Amount_1..Amount_10, UTR, UTR_2..UTR_10, Date_1..Date_10
```

### Contacts (investor)
```
First_Name, Last_Name (required), Email, Mobile, Phone,
Salutation, Description
```
