# Marketplace project lifecycle — ops runbook

**Audience.** Ops engineers and admins (non-developer). You will be reading
this when a project needs to go live on the Explore tab, when an investor
asks "why doesn't my project show up", or when unit counts on a card look
wrong. You'll spend most of your time in Supabase Studio (SQL editor) and
in Zoho CRM. You will not need to touch Flutter source.

**Scope.** Everything that controls what appears on the Explore tab in
the investor app, how it appears, and how unit counts flow from Zoho into
those cards. Adjacent flows (consultation requests, exit requests,
financials) are covered in their own docs.

**Last verified.** 2026-05-15 against Supabase project
`oynfhdqizebvgmaoiuax`, commit `3ad408e` (after `2d3ddae` shipped the
strict filter fix).

---

## 1. Mental model

```
   Zoho CRM                  Supabase                   Investor app
+------------+      +----------------------+      +------------------+
| LLP_       |      | webhook_log          |      | Explore tab      |
| Creation_  |  ->  | (audit, idempotent)  |  ->  | (Coming Soon /   |
| Module     |      |                      |      |  Open for        |
|            |      | llps   (legal+SPOC)  |      |  Reservation)    |
|            |      | projects (units +    |      |                  |
|            |      |   marketplace flags) |      |                  |
+------------+      +----------------------+      +------------------+
       |                       ^
       |   zoho-crm-webhook    |   manual UPDATEs in Studio
       +-----------------------+   (is_listed_in_marketplace, tagline,
                                   subscription_deadline, sort_order,
                                   marketplace_image)
+------------+      +----------------------+
| LLP_Unit   |      | investor_units       |
| Allocation_|  ->  | (one row per         |
| Module     |      |  investor x project) |
+------------+      | + payouts (UTR fan)  |
                    +----------------------+
```

Three modules in Zoho fan out into Supabase rows via the
`zoho-crm-webhook` edge function. A daily `zoho-reconcile-daily` cron
function does a pull-side safety net for missed webhooks.

The cards on Explore are driven entirely by rows in `public.projects`
where `is_listed_in_marketplace = true` and `deleted_at IS NULL`. There
is no separate "marketplace" table; the flag IS the marketplace
membership.

**The single most important thing to internalise**: Zoho is the source
of truth for `total_units`, `units_issued`, and `units_available`. All
three are pulled from the Zoho LLP record on every webhook fire AND on
every daily reconcile pass. Anything you write directly to these columns
in Supabase will be overwritten the next time the LLP is modified in
Zoho. See section 6 for why this matters and what the workaround is.

---

## 2. Schema reference

### `public.projects` (marketplace-relevant columns)

| Column                    | Type     | Source                          | Notes                                                                                 |
|---------------------------|----------|---------------------------------|---------------------------------------------------------------------------------------|
| `id`                      | uuid     | Zoho LLP id (1:1 by convention) | PK. Identical to `llp_id`.                                                            |
| `llp_id`                  | uuid     | Zoho                            | FK to `llps.id`. Webhook keeps `projects.id == llps.id` for default 1:1.              |
| `name`                    | text     | Zoho `Name`                     | Card title. Webhook overwrites.                                                       |
| `tier`                    | text     | Zoho `Tier`                     | Card metadata.                                                                        |
| `status`                  | text     | Zoho `LLP_Status`               | Free-text. Not a CHECK enum. Drives `is_listed_in_marketplace` recomputation.         |
| `total_units`             | int      | Zoho `Total_Units`              | Webhook overwrites on every LLP sync.                                                 |
| `units_issued`            | int      | Zoho `Units_Issued`             | Webhook overwrites. NOT auto-derived from `investor_units` — see Section 6.            |
| `units_available`         | int      | Zoho `Units_Available_to_Issue` | Webhook overwrites. NOT auto-derived. NOT a generated column.                          |
| `price_per_unit`          | numeric  | Zoho `Pet_Unit_Price`           | Yes, that field name is misspelled upstream.                                          |
| `expected_annual_return_pct` | numeric | Supabase only                 | Set manually. Card shows this; if NULL the card falls back to `annual_yield_pct`.     |
| `subscription_deadline`   | date     | Supabase only                   | Set manually. Drives `isClosed` in app: if past, card greys out.                       |
| `is_listed_in_marketplace`| bool     | Webhook + manual                | Webhook sets `true` when `LLP_Status` is "Open for Reservation" or "Open for Issuance". |
| `marketplace_sort_order`  | int      | Supabase only                   | Default 0. Lower = appears first. Set manually.                                       |
| `marketplace_image`       | text     | Supabase only                   | Storage path or full URL. Set manually.                                               |
| `tagline`                 | text     | Supabase only                   | One-line pitch shown on the gradient detail card. Set manually.                       |
| `deleted_at`              | tstz     | Webhook (LLP delete)            | Soft delete. Webhook sets when Zoho deletes the LLP.                                  |

### `public.investor_units` (allocation-relevant columns)

| Column                | Type | Source                          | Notes                                                                          |
|-----------------------|------|---------------------------------|--------------------------------------------------------------------------------|
| `id`                  | uuid | Supabase                        | PK.                                                                            |
| `zoho_allocation_id`  | text | Zoho                            | Unique. The webhook upserts on this.                                           |
| `investor_id`         | uuid | Resolved from Zoho `Customer.id`| FK to `investors`.                                                             |
| `project_id`          | uuid | Resolved via `llps.zoho_llp_id` | FK to `projects`.                                                              |
| `issued_units`        | int  | Zoho `Issued_Units`             | Per-investor count.                                                            |
| `reserved_units`      | int  | Zoho `Reserved_Units`           | Per-investor reservation.                                                      |
| `allocation_status`   | text | Zoho `Allocation_Status`        | Free-text. No CHECK enum (verified — only PK / FK / unique constraints exist). |
| `deleted_at`          | tstz | Webhook                         | Soft delete.                                                                   |

Note: `investor_units` has **no** CHECK constraint on `allocation_status`
(or any other column). Anything Zoho sends goes in.

### Generated columns / triggers / views

Confirmed by the database introspection:

- `units_available` is **not** a generated column.
  `information_schema.columns.is_generated = 'NEVER'` for all three of
  `total_units`, `units_issued`, `units_available`.
- The only non-internal triggers on `projects` and `investor_units` are
  the boring `set_updated_at()` triggers (`trg_projects_updated_at`,
  `trg_investor_units_updated_at`). Neither touches unit counts.
- `projects_public` is a view that filters
  `WHERE deleted_at IS NULL` — same columns, no derived ones.
- `portfolio_summary` is a view but it aggregates `investor_units`
  for portfolio totals; it does not write back to `projects`.

So: `projects.units_available` is a plain integer column that whoever
writes to it last wins. In practice, the only writer is the Zoho
webhook (and reconcile job).

---

## 3. Explore filter logic

File: `lib/features/explore/explore_screen.dart` (function `_applyFilter`).
Model: `lib/features/projects/models/marketplace_project.dart`.

The Explore screen pulls everything from `public.projects` where
`is_listed_in_marketplace = true` and partitions client-side into three
tabs:

| Tab pill              | Internal value  | Predicate                                                                                                       |
|-----------------------|-----------------|-----------------------------------------------------------------------------------------------------------------|
| All                   | `all`           | every marketplace listing, no filter                                                                            |
| Open for Reservation  | `open`          | `isOpenForReservation` => `!isClosed && unitsAvailable > 0 && unitsAvailable < totalUnits`                      |
| Coming soon           | `not_started`   | `isComingSoon`         => `!isClosed && unitsAvailable == totalUnits`                                            |

Both `isOpenForReservation` and `isComingSoon` also imply `!isClosed`,
where `isClosed` means `subscription_deadline` is in the past.

The two getters from the Dart model (quoted verbatim):

```dart
bool get isComingSoon => !isClosed && unitsAvailable == totalUnits;

bool get isOpenForReservation =>
    !isClosed && unitsAvailable > 0 && unitsAvailable < totalUnits;
```

The two filters are mutually exclusive by construction: a listing where
`unitsAvailable == totalUnits` cannot also have
`unitsAvailable < totalUnits`. A fully-subscribed listing
(`unitsAvailable == 0`) appears in neither — by intent. A
deadline-expired listing appears in neither.

### What changed in commit 2d3ddae

Before: `open` was `!isClosed && unitsAvailable > 0` — which matched
brand-new listings where `unitsAvailable == totalUnits`. So a fresh
listing leaked into both Open and Coming Soon.

After: the two predicates are partitioned on `unitsAvailable <
totalUnits` vs `unitsAvailable == totalUnits`. A fresh listing is now
exclusively Coming Soon until the first allocation is recorded in Zoho
and re-syncs to Supabase.

Decision note: `.claude/decisions/2026-05-14_explore-strict-filter.md`.

### Verification SQL

Run this any time you want to know which tab each project lands in:

```sql
SELECT name, total_units, units_issued, units_available, subscription_deadline,
  CASE
    WHEN subscription_deadline IS NOT NULL AND subscription_deadline < now() THEN 'closed'
    WHEN units_available = total_units THEN 'coming_soon'
    WHEN units_available > 0 THEN 'open'
    ELSE 'sold_out'
  END AS bucket
FROM projects
WHERE is_listed_in_marketplace = true AND deleted_at IS NULL
ORDER BY bucket, marketplace_sort_order;
```

Each row should fall in exactly one bucket.

---

## 4. Zoho -> Supabase sync detail (what the webhook does)

File: `supabase/functions/zoho-crm-webhook/index.ts`.

When a Zoho workflow fires on `LLP_Creation_Module` (any create/update),
the webhook calls `handleProject(d)` which:

1. Upserts the `llps` row keyed on `zoho_llp_id`. Captures legal,
   registered-address, and SPOC fields.
2. Looks up the default project under that LLP (`llp_id = llp.id`).
3. Writes/updates the project with these fields (excerpted):

```
total_units             = Total_Units
units_issued            = Units_Issued
units_available         = Units_Available_to_Issue
price_per_unit          = Pet_Unit_Price
status                  = LLP_Status
is_listed_in_marketplace = LLP_Status in ('Open for Reservation','Open for Issuance')
```

So both the unit counts AND the marketplace flag get recomputed from
Zoho on every LLP record save. That has two implications:

- If ops wants a project to appear on the marketplace, the cleanest path
  is to set its Zoho `LLP_Status` to "Open for Reservation" — the
  webhook will toggle the flag on next sync. (Manually flipping the flag
  in Supabase works too, until the next LLP edit in Zoho clobbers it.)
- If ops wants to hide a project from the marketplace, the cleanest path
  is to change its Zoho `LLP_Status` away from those two values. The
  list of states that hide the project today: "Active", "Fully
  Subscribed / Closed", "Darft" (sic), "Completed", anything else.

For `LLP_UnitAllocation_Module` (any create/update on an allocation),
the webhook calls `handleAllocation(d)` which:

1. Resolves the investor (by `Customer.id` -> `investors.zoho_contact_id`).
2. Resolves the LLP, then its default project.
3. Upserts an `investor_units` row keyed on `zoho_allocation_id`.
4. Unpacks UTR_1..10/Amount_1..10/Date_1..10 fan into `payouts` rows.
5. Inserts a notification row for the investor.

Note carefully: **`handleAllocation` does NOT touch
`projects.units_issued` or `projects.units_available`.** Those two
columns only move when the LLP record itself is re-saved in Zoho. See
the next section for why that creates a visible drift problem.

---

## 5. Live test results (run 2026-05-15)

### Current state of demo + active marketplace projects

```
name                          total  issued  available  marketplace
Alpha Avocado LLP-demo        500    0       500        true   (Coming Soon)
Growize Test LLP              44     1       43         true   (Open)
Pineapple Enterprises         80     19      61         true   (Open)  deadline 2026-09-30
Samsung LLP                   44     0       44         true   (Coming Soon)  deadline 2026-12-31
Test First LLP                20     1       19         true   (Open)
UAT End-to-End LLP 2026-05-11 100    0       100        true   (Coming Soon)
UAT Test LLP 01               20     NULL    20         true   (Coming Soon, NULL units_issued)
UAT Test LLP 02               50     NULL    50         true   (Coming Soon, NULL units_issued)
```

Predicted Explore tabs (deterministic from the filter logic above):

- **All:** 8 listings.
- **Open for Reservation:** Growize Test LLP, Pineapple Enterprises,
  Test First LLP.
- **Coming Soon:** Alpha Avocado LLP-demo, Samsung LLP, UAT End-to-End
  LLP 2026-05-11, UAT Test LLP 01, UAT Test LLP 02.

### Invariant check (`total_units = units_issued + units_available`)

Computed for every project:

```
name                            total  issued  available  invariant_ok?
Alpha Avocado LLP-demo          500    0       500        OK
Alpha Mango LLP-demo            1000   90      910        OK
Beta Banana LLP-demo            800    120     680        OK
Delta Exited LLP-demo           600    20      580        OK
Gamma Empty LLP-demo            0      NULL    NULL       OK-ish (all NULL)
Gamma Grape LLP-demo            500    0       500        OK
Growize Test LLP                44     1       43         OK
Pineapple Enterprises           80     19      61         OK
Sample Test LLP                 20     50      -30        BROKEN (issued > total, available negative)
Samsung LLP                     44     0       44         OK
Test First LLP                  20     1       19         OK
UAT End-to-End LLP 2026-05-11   100    0       100        OK
UAT Test LLP 01                 20     NULL    20         OK-ish (NULL == 0)
UAT Test LLP 02                 50     NULL    50         OK-ish
Xiaomi LLP                      120    0       120        OK
```

`Sample Test LLP` is **broken at source** — Zoho sent `Units_Issued =
50` for a 20-unit project. The Explore filter excludes it (it's
`is_listed_in_marketplace = false`), so it's not user-visible, but it's
worth chasing upstream. See defects.

### Drift check (`sum(investor_units.issued_units)` vs `projects.units_issued`)

For every project where investor_units rows exist, we expect
`sum(iu.issued_units) <= projects.units_issued` (Zoho's count of issued
units across all allocations should match or exceed our local sum,
because Zoho is the source of truth and could legitimately have
allocations our webhook missed). Found mismatches:

```
project                        proj.units_issued   sum(iu.issued_units)   drift
Beta Banana LLP-demo           120                 20                     -100  (Zoho says 120, we have 20)
Pineapple Enterprises          19                  4                      -15
Samsung LLP                    0                   5                      +5  (we have units, Zoho says none)
UAT End-to-End LLP 2026-05-11  0                   5                      +5
Xiaomi LLP                     0                   7                      +7
```

The +5/+5/+7 drift on Samsung, UAT End-to-End, and Xiaomi is the
fingerprint of the missing auto-balance: someone (probably the webhook
processing an allocation) inserted `investor_units` rows but the parent
LLP wasn't re-saved in Zoho, so `projects.units_issued` was never
re-pulled. The negative drift on Beta Banana / Pineapple is the
opposite case — the LLP-level Zoho count is real but our local
`investor_units` table only mirrors the small subset that has been
allocated through the webhook so far.

### Allocation test: does inserting an `investor_units` row update `projects`?

```sql
-- Before
SELECT total_units, units_issued, units_available FROM projects WHERE name ILIKE '%banana%';
-- 800, 120, 680

-- Insert one issued unit for test investor on Beta Banana
INSERT INTO investor_units (investor_id, project_id, issued_units, reserved_units, allocation_status)
SELECT '27d3735e-470d-47a5-a413-9ae502194d3d', p.id, 1, 0, 'Issued'
FROM projects p WHERE p.name ILIKE '%banana%' LIMIT 1;

-- After
SELECT total_units, units_issued, units_available FROM projects WHERE name ILIKE '%banana%';
-- 800, 120, 680   <-- UNCHANGED
```

Confirmed: `projects.units_issued` and `projects.units_available` do
NOT auto-update when an `investor_units` row is inserted. (Synthetic
row was deleted as cleanup.) The columns are static; only the Zoho
LLP-level webhook moves them.

---

## 6. Auto-balance investigation and decision

### Symptom

`projects.units_available` can drift away from "true" availability
because:

- The LLP webhook pulls `units_issued` and `units_available` from the
  Zoho LLP record fields.
- The allocation webhook inserts/updates `investor_units` rows but does
  NOT update the project's aggregate counters.
- The two paths can fire out of order, and there's no per-row
  invariant. Result: drift like Samsung LLP showing 0 issued on the
  card while 5 `investor_units` rows exist locally.

### Could we add a trigger to recompute?

```sql
-- HYPOTHETICAL — NOT APPLIED
CREATE OR REPLACE FUNCTION recompute_project_units()
RETURNS trigger AS $$
DECLARE
  pid uuid := COALESCE(NEW.project_id, OLD.project_id);
  sum_issued int;
BEGIN
  SELECT COALESCE(SUM(issued_units), 0) INTO sum_issued
  FROM investor_units
  WHERE project_id = pid AND deleted_at IS NULL;
  UPDATE projects
  SET units_issued    = sum_issued,
      units_available = GREATEST(total_units - sum_issued, 0)
  WHERE id = pid;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
```

This would fight with the Zoho webhook every time an LLP record is
saved in Zoho. Sequence:

1. Zoho LLP modified -> webhook fires `handleProject` -> sets
   `units_issued = 120` (Zoho's number).
2. A second later, Zoho fires `handleAllocation` for a new
   `investor_units` row -> our hypothetical trigger fires -> sets
   `units_issued = 20` (our local sum, smaller than Zoho's).
3. Card shows 20 issued, then 120, then back to 20 depending on which
   handler fires last.

The race is real. Zoho's `Units_Issued` count is the canonical figure
across all allocation history (including legacy ones not in our
`investor_units` mirror). Our local sum is only the subset that has
fanned out through the webhook into `investor_units`. They are not the
same number, and a trigger that overrides Zoho will permanently
under-count.

### Could `units_available` be a GENERATED column?

`GENERATED ALWAYS AS (GREATEST(total_units - units_issued, 0)) STORED`
is plausible IF and only if `units_issued` is itself canonical (i.e.,
Zoho's count, not our local sum). It is canonical today — Zoho
populates it. Adding the generated column would mean:

- The webhook can no longer write to `units_available` directly. We'd
  need to strip that field from `handleProject` and `reconcileLlps`.
- Anyone (Studio user) trying to `UPDATE projects SET units_available
  = X` would get an error.

This is the **safest** improvement, but it's not free: it touches the
edge function and changes the failure mode of manual updates. It's
worth doing in a planned change, not in this audit.

### Decision

**Do not ship the trigger. Do not ship the GENERATED column right now.**
Document the manual reconcile chore (recipe M-5 below) and surface the
drift in monitoring instead.

**Recommendation for a future migration** (write up; do NOT apply now):

1. Add `units_available` as `GENERATED ALWAYS AS (GREATEST(total_units
   - units_issued, 0)) STORED`.
2. Same migration: remove `units_available` from the field map in both
   `handleProject` (webhook) AND `reconcileLlps` (cron).
3. Backfill: the generated value will be set automatically on the
   first ALTER. Verify Sample Test LLP becomes `0` (current `-30`
   value will be `GREATEST(20 - 50, 0) = 0`).
4. Keep `units_issued` writable by Zoho — that remains the source of
   truth.

Requires a code change in `supabase/functions/zoho-crm-webhook/index.ts`
and `supabase/functions/zoho-reconcile-daily/index.ts`, so it's
beyond the scope of this ops doc.

---

## 7. Ops recipes

The recipes below assume:

- You have Supabase Studio access to `oynfhdqizebvgmaoiuax`.
- You know the project's `id` or `name` (look it up first).
- You're running SQL in the SQL Editor, not via psql. Always wrap
  multi-statement ops in a transaction (`BEGIN; ... COMMIT;`).

### M-1. List a new project in the marketplace

Two paths. Path A is the canonical one.

**Path A (preferred — go through Zoho).** In Zoho CRM, find the LLP
record and set `LLP_Status` to `Open for Reservation`. Save. The
webhook fires within seconds and Supabase will reflect:

```sql
SELECT name, status, is_listed_in_marketplace
FROM projects WHERE name ILIKE '%your-project%';
-- expect: status = 'Open for Reservation', is_listed_in_marketplace = true
```

Why preferred: the webhook will keep flipping the flag back to the
right value every time someone touches the LLP in Zoho. Path B fights
that.

**Path B (Studio override).** If you can't get into Zoho for some
reason:

```sql
UPDATE projects
SET is_listed_in_marketplace = true,
    updated_at = now()
WHERE id = '<project_uuid>';
```

Caveat: the next time anyone saves that LLP in Zoho with a different
`LLP_Status`, the webhook will overwrite `is_listed_in_marketplace`
back to `false`. Use Path B only as a same-day-fix and update Zoho
afterwards.

### M-2. Mark a project as Coming Soon

A project shows as "Coming Soon" on Explore when:

- `is_listed_in_marketplace = true`
- `subscription_deadline` is in the future (or NULL)
- `units_available = total_units` (zero issued — fresh placeholder)

Coming Soon is mostly a passive state — it's the default when a project
is first listed before anyone has been allocated.

To force a project into Coming Soon (e.g., for a launch announcement
while allocations exist):

```sql
-- Don't do this lightly — it lies about the allocation state to investors.
UPDATE projects
SET units_issued = 0,
    units_available = total_units,
    updated_at = now()
WHERE id = '<project_uuid>';
```

This will be overwritten on the next Zoho LLP sync. Don't do it.

### M-3. Mark a project as Open for Reservation

The Explore "Open for Reservation" filter requires:

- `is_listed_in_marketplace = true`
- `units_available < total_units` (at least one issued unit, so the
  listing is "live")
- `units_available > 0`
- `subscription_deadline` is in the future or NULL

In practice, "Open for Reservation" happens automatically once the
first allocation is recorded in Zoho (it fans out to `investor_units`
and the LLP's `Units_Issued` ticks up the next time the LLP is
re-saved). If you want to force it before there's a real allocation:

```sql
-- Force one issued unit so the card flips out of Coming Soon. Manual
-- reconcile required afterwards (recipe M-5) once a real allocation lands.
UPDATE projects
SET units_issued = 1,
    units_available = total_units - 1,
    is_listed_in_marketplace = true,
    updated_at = now()
WHERE id = '<project_uuid>';
```

Again: any Zoho LLP edit will revert this. Real way: get the first
allocation into Zoho.

### M-4. Update the marketplace card (image / tagline / deadline / sort)

These four fields are 100% Supabase-side. Zoho never touches them.

```sql
UPDATE projects
SET tagline = 'Hand-tended avocado groves in Karnataka',
    marketplace_image = 'https://<cdn-host>/cards/alpha-avocado.jpg',
    subscription_deadline = '2026-08-31',
    marketplace_sort_order = 1,
    updated_at = now()
WHERE id = '<project_uuid>';
```

Field notes:

- `tagline`: free text, shown under the project name on the gradient
  detail card on Explore. ~70 char target.
- `marketplace_image`: stored as a string. The Flutter code passes it
  through as `String?`; an external URL is the safest format. (Storage
  paths would need the app to know the bucket — not used today.)
  The current card does not actually render an image; if/when it
  does, this field is the source.
- `subscription_deadline`: a DATE. If past, `isClosed` flips to true
  and the card greys out (no filter shows it).
- `marketplace_sort_order`: integer. Lower numbers first. Default 0;
  Pineapple Enterprises is currently the only project with a non-zero
  value (set to 1, Samsung LLP to 2).

Verify after:

```sql
SELECT name, tagline, marketplace_image, subscription_deadline, marketplace_sort_order
FROM projects WHERE id = '<project_uuid>';
```

### M-5. Manually reconcile units_available (the chore)

Use this when an investor reports "the card says 19 units available but
I just got allocated unit #19" — i.e., `projects.units_available`
hasn't caught up.

**Step 1.** Pick the source of truth. Two options:

- (a) Zoho LLP. Trigger a re-save of the LLP record in Zoho (no edits
  needed — just save). The webhook fires `handleProject` and pulls
  the canonical `Units_Issued` from the Zoho LLP record. This is
  preferred — it's the same value users see on the desk side.
- (b) Local `investor_units` sum. Use this only when (a) is impossible
  (Zoho down, webhook broken). It's the local view and may undercount
  if some allocations were never synced.

**Step 2(a).** Trigger Zoho re-save. No SQL needed. Wait ~5 seconds.
Verify:

```sql
SELECT name, total_units, units_issued, units_available, last_synced_at
FROM projects WHERE id = '<project_uuid>';
```

`last_synced_at` should be within the last minute.

**Step 2(b).** Local-sum fallback:

```sql
WITH agg AS (
  SELECT project_id, COALESCE(SUM(issued_units), 0) AS sum_issued
  FROM investor_units
  WHERE project_id = '<project_uuid>' AND deleted_at IS NULL
  GROUP BY project_id
)
UPDATE projects p
SET units_issued    = agg.sum_issued,
    units_available = GREATEST(p.total_units - agg.sum_issued, 0),
    updated_at      = now()
FROM agg
WHERE p.id = agg.project_id
RETURNING p.id, p.name, p.total_units, p.units_issued, p.units_available;
```

After this manual fix, the next Zoho LLP save will overwrite again.
Make sure Zoho is correct or you'll just chase your tail.

**Bulk drift check.** Spot all projects with `units_issued !=
sum(iu.issued_units)`:

```sql
SELECT p.name, p.units_issued AS proj_issued,
       COALESCE(SUM(iu.issued_units), 0) AS local_sum,
       p.units_issued - COALESCE(SUM(iu.issued_units), 0) AS drift
FROM projects p
LEFT JOIN investor_units iu ON iu.project_id = p.id AND iu.deleted_at IS NULL
WHERE p.deleted_at IS NULL
GROUP BY p.id, p.name, p.units_issued
HAVING p.units_issued IS DISTINCT FROM COALESCE(SUM(iu.issued_units), 0)
ORDER BY ABS(p.units_issued - COALESCE(SUM(iu.issued_units), 0)) DESC;
```

### M-6. Sunset a project (close it on the marketplace)

Three flavours of "close":

(a) **Subscription window closed but project still live** (typical for
a successful raise). Set the deadline in the past; Explore stops
showing it automatically:

```sql
UPDATE projects
SET subscription_deadline = (now() - interval '1 day')::date,
    updated_at = now()
WHERE id = '<project_uuid>';
```

The card moves into `isClosed` state and disappears from both Open and
Coming Soon tabs (it'd still appear under "All" since "All" doesn't
filter on `isClosed`, but the status badge shows "Closed").

(b) **Hide from marketplace entirely** (project still operational for
existing investors):

```sql
UPDATE projects
SET is_listed_in_marketplace = false,
    updated_at = now()
WHERE id = '<project_uuid>';
```

Don't forget the Zoho LLP status — if `LLP_Status` stays at "Open for
Reservation", the next webhook fire will re-flip the flag to true.
Either change `LLP_Status` in Zoho first or accept that any LLP save
will undo this.

(c) **Soft-delete the project** (orphan it for audit but kill it
everywhere):

Preferred path is to delete the LLP record in Zoho — the webhook's
`handleLLPDelete` will cascade and set `deleted_at` on the project
plus the LLP row. Manual override:

```sql
UPDATE projects
SET deleted_at = now(),
    is_listed_in_marketplace = false,
    updated_at = now()
WHERE id = '<project_uuid>';
```

`projects_public` and the marketplace query both filter
`deleted_at IS NULL`, so a soft-deleted project disappears from
everywhere except direct admin reads.

### Sort order — how marketplace_sort_order is used today

The repository's marketplace query reads in
`marketplace_sort_order ASC, name ASC` order. Set lower values for
projects you want to appear first.

Current order (just the marketplace-listed rows):

```
sort  name
0     Alpha Avocado LLP-demo
0     Growize Test LLP
0     Test First LLP
0     UAT End-to-End LLP 2026-05-11
0     UAT Test LLP 01
0     UAT Test LLP 02
1     Pineapple Enterprises
2     Samsung LLP
```

In practice the zero-bucket is alphabetised. To put Pineapple and
Samsung above the rest:

```sql
UPDATE projects SET marketplace_sort_order = -10 WHERE id = '<pineapple_uuid>';
UPDATE projects SET marketplace_sort_order = -9  WHERE id = '<samsung_uuid>';
```

---

## 8. Defects + open questions

### P1

- **DEF-MKT-01 — Sample Test LLP has `units_available = -30`.**
  Source: Zoho sent `Units_Issued = 50` for a `Total_Units = 20`
  project. Currently hidden from Explore (not marketplace-listed), so
  no user impact, but it indicates Zoho-side data entry that was never
  validated. Suggest: add a CHECK constraint
  `CHECK (units_available >= 0)` or
  `CHECK (units_issued <= total_units)` on `projects`. Both would
  reject the offending Zoho payload at write time and surface the bad
  data via the webhook's error path.

### P2

- **DEF-MKT-02 — `projects.units_issued` drift vs
  `sum(investor_units.issued_units)`.** Samsung LLP (+5), UAT
  End-to-End LLP (+5), Xiaomi LLP (+7) — `investor_units` rows exist
  locally but the parent project shows zero issued. Means the
  marketplace card under-reports issued units. Recipe M-5 is the
  workaround; a generated column for `units_available` plus an
  occasional Zoho LLP re-save are the structural fix. See section 6.

- **DEF-MKT-03 — `units_issued` can be NULL for projects with
  `units_available != NULL`.** UAT Test LLP 01 / 02 have
  `units_issued = NULL, units_available = 20`. The Dart model coerces
  NULL to 0 via `(num?)?.toInt() ?? 0`, so the cards render correctly,
  but the invariant `total_units = units_issued + units_available`
  is undefined. Probably a Zoho-side issue (the field was never set).
  Suggest defaulting `units_issued` to 0 in the projects schema —
  cheap, low-risk:
  `ALTER TABLE projects ALTER COLUMN units_issued SET DEFAULT 0;`
  plus a one-off `UPDATE projects SET units_issued = 0 WHERE
  units_issued IS NULL;`.

### P3

- **DEF-MKT-04 — `marketplace_sort_order` is mostly unused.** 6 of 8
  listed projects have `sort_order = 0`. No clear ops convention for
  what number to use. Document a convention (e.g., "use 100 by default
  so you can insert above and below without renumbering") or ignore.

- **DEF-MKT-05 — Status free-text typo `Darft`.** Visible on Gamma
  Empty LLP-demo. Cosmetic in demo data. The webhook does derive
  `is_listed_in_marketplace` from a fixed allow-list (`'Open for
  Reservation'`, `'Open for Issuance'`), so a typo like `Darft` cannot
  accidentally flip the marketplace flag. No user impact; flag for
  Zoho-side picklist cleanup.

### Open questions

- The `marketplace_image` field is in the schema but the current
  Explore card UI does not render an image. Either (a) the field was
  added in anticipation of a future card redesign and is dormant, or
  (b) the design exists but isn't wired yet. Investigate before
  asking ops to populate it for every listing.
- `expected_annual_return_pct` is Supabase-only — no Zoho field maps
  to it. Either the figure is set manually per launch, or a different
  Zoho field needs to be mapped. Confirm with the desk/finance team
  which side owns this number.
- `cropType` is referenced in the Dart model
  (`r['crop_type'] as String?`) but no `crop_type` column exists on
  `projects` today. Means every card shows `null` for "Crop". Either
  add the column or strip the row from the card.

---

## 9. Migration references

- `001_investors_and_projects` — initial schema for `projects`.
- `009_split_llp_from_project` — added `llp_id`; introduced the 1:1
  `llps`/`projects` split that the webhook relies on.
- `034_projects_public_view` — current `projects_public` view filtering
  `deleted_at IS NULL`.
- `037_soft_delete_columns` — added `deleted_at` to projects, llps,
  investor_units, investors.
- `038_soft_delete_rls` — RLS hides soft-deleted rows from app reads.
- `042_investor_units_soft_delete` — DEF-10 fix; webhook now writes
  soft-delete instead of hard-delete.
- `045_consultation_slack_trigger` — most recent applied migration
  (2026-05-14).

**Migrations NOT applied during this audit.** No DDL was shipped. The
auto-balance investigation concluded the trigger approach would race
with the Zoho webhook (see section 6). A future migration `046` could
add `units_available` as a GENERATED column **paired with** edge-
function changes to stop writing that field, but that's a planned
change requiring code review, not an ops-doc deliverable.

---

## Appendix: where to look next

- For Zoho-side workflow setup (`Push_LLP_To_Supabase` Deluge function):
  see `docs/zoho-config.md` (if it exists; otherwise ask the ops
  channel).
- For webhook-handler source: `supabase/functions/zoho-crm-webhook/index.ts`.
- For reconcile-cron source: `supabase/functions/zoho-reconcile-daily/index.ts`.
- For the Flutter filter logic:
  `lib/features/explore/explore_screen.dart` (the `_applyFilter`
  function) and `lib/features/projects/models/marketplace_project.dart`
  (the predicate getters).
- For prior decisions:
  `.claude/decisions/2026-05-14_explore-strict-filter.md`.
