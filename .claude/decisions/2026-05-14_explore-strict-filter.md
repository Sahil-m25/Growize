# 2026-05-14 — Strict partition between Explore filters

## Problem
UAT: switching between "Open for Reservation" and "Coming Soon" leaked listings across — some items showed in both.

## Root cause
Predicates overlapped:
- `open` was `!isClosed && unitsAvailable > 0` — matched fresh listings where `unitsAvailable == totalUnits`.
- `not_started` was `unitsAvailable == totalUnits` — also matched the same fresh listings.

So any project with `unitsAvailable > 0 && unitsAvailable == totalUnits` was returned by both filters.

## Why not the DB `status` column
`public.projects.status` has CHECK `IN ('pending','operational','completed')` — a lifecycle column, not a marketplace-visibility one. The Zoho-driven free-text `llp_status` ("Open for Issuance", "Closed", etc.) is not authoritative either. The marketplace already derives its open/coming-soon state from `units_available` and `subscription_deadline`; the bug was in client logic, not in the schema. No migration needed.

## Fix
Added two strict, mutually-exclusive getters on `MarketplaceProject`:
- `isComingSoon` = `!isClosed && unitsAvailable == totalUnits`
- `isOpenForReservation` = `!isClosed && unitsAvailable > 0 && unitsAvailable < totalUnits`

`_applyFilter` now routes through those getters. Closed listings appear in neither filter (matches prior behaviour). The legacy `isNotYetStarted` getter is kept as the underlying signal.

## Verification SQL (run by orchestrator if needed)
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
Each row should land in exactly one bucket.

## Files changed
- `lib/features/projects/models/marketplace_project.dart`
- `lib/features/explore/explore_screen.dart`

## Verification
`dart analyze lib` clean.
