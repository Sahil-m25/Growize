# 2026-05-15 — projects units columns become derived

**Status:** Implemented in migration 046 + webhook v2.

## Context

Two open defects:

- **DEF-2026-05-15-01 (S2/P1):** Zoho sent a Sample Test LLP payload
  with `Units_Issued=50` for `Total_Units=20`, leaving
  `units_available=-30`. No DB-level guard exists.
- **DEF-2026-05-15-05 (S3/P2):** 5 projects drift between
  `projects.units_issued` (Zoho-supplied) and
  `SUM(investor_units.issued_units)` (per-allocation truth).
  Marketplace cards under-report.

Both stem from the same architectural confusion: `projects.units_issued`
is written by two sources — the LLP webhook (Zoho's authoritative
counter) and (implicitly) the allocations webhook (which writes the
investor_units rows but never reconciles the parent counter).

## Decision

Pick a single source of truth: **`investor_units` is canonical.**

- `total_units` stays Zoho-sourced (LLP-level, static).
- `units_issued` becomes derived: `SUM(investor_units.issued_units)`
  filtered to active (`deleted_at IS NULL`) + `allocation_status='Issued'`.
- `units_available` becomes derived: `GREATEST(total_units - units_issued, 0)`.
- Zoho webhook stops writing `units_issued` and `units_available`.
- A trigger on `investor_units` recomputes the parent project row on
  every insert/update/delete.
- CHECK constraint `projects_units_nonneg` rejects future Zoho payloads
  that would violate `units_issued >= 0 AND units_issued <= total_units
  AND units_available >= 0`.

Postgres GENERATED columns can't aggregate across tables, so the
"derived" semantics are realised via a trigger; the column shape stays
the same for callers.

## Trade-offs

- Pro: single writer, invariant enforced at the DB level, marketplace
  cards now match per-allocation reality.
- Con: bootstrap impact — projects with NULL `allocation_status` rows
  (DEF-2026-05-07-02, still open) recompute to `units_issued=0` even
  if the Zoho LLP said otherwise. The fix-forward is to backfill
  `allocation_status='Issued'` on the affected `investor_units` rows.
  Migration 046 logs this in the row's `name` for Sample Test LLP-style
  invariant violations.
- Con: trigger fires on every allocation write; with 8 listed projects
  + 25 investor_units rows the cost is negligible, but a future scale
  ceiling exists. Reconsider if write throughput on `investor_units`
  ever climbs.

## Rollback

Drop the CHECK + trigger + functions; restore prior values from a
snapshot if needed (the migration also nulls the offending Sample Test
LLP row name with `[ops: needs cleanup]`).
