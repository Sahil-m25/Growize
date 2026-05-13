# Decision — Document tiering (common / project / investor)

**Date:** 2026-05-13
**Status:** locked
**Scope:** FG-05 from e2e_test_plan_v2_extended_2026-05-13.md

## Problem
`public.documents` only supports per-investor documents
(`investor_id NOT NULL`). Ops needs to publish:
- Common documents (brand-wide prospectus, sample agreements,
  brand-level compliance) visible to every investor.
- Project documents (project-specific deeds, crop reports,
  insurance docs) visible only to investors holding units in
  that project.
Today both would need to be replicated N times per investor —
expensive at scale, easy to drift out of sync.

## Decision
Split documents into three tiers via a new `visibility` column
plus a tier-aware RLS policy + storage policy + CHECK constraint
that keeps `investor_id` / `project_id` mutually exclusive per tier.

## What changed

### Schema (migration 032)
- `visibility TEXT NOT NULL DEFAULT 'investor'` with CHECK in
  (`common`, `project`, `investor`).
- `project_id UUID REFERENCES projects(id) ON DELETE SET NULL` —
  required for the project tier. Set-null on parent delete so
  soft-deleting a project doesn't orphan-cascade documents.
- `investor_id` becomes nullable.
- CHECK `documents_tier_columns_check` enforces the
  tier → (investor_id, project_id) presence invariant.
- Indexes on `(visibility, uploaded_at DESC)` and partial
  `(project_id, uploaded_at DESC)` for the project tier.

### RLS (migration 033)
- Drops legacy `documents: read own rows`, installs
  `documents: tiered read`:
  - common → all authenticated
  - project → `project_id IN (SELECT project_id FROM
    investor_units WHERE investor_id = auth.uid())`
  - investor → `investor_id = auth.uid()`.
- New `documents: insert own investor doc`: investor-tier only,
  scoped to own `auth.uid()`. Common + project uploads are
  service-role only by design (Studio or Edge Function).
- Storage RLS mirrors the same shape with three per-tier read
  policies on `arl-documents`:
  - `common/*` → all authenticated
  - `project/<project_id>/*` → unit-holders
  - `investor/<auth.uid()>/*` → owner only.

### App
- `InvestorDocument` model picks up `visibility` + `projectId`
  from the row, defaulting to `investor` so a stale row still
  renders.
- `DocumentsScreen` no longer groups by `doc_type`. It renders
  three fixed-order accordions — **Common** / **My Projects** /
  **My Documents** — and an inline empty placeholder per
  accordion when that tier is empty. Global empty-state still
  fires when ALL three are empty.
- `DocumentsRepository.myDocuments()` unchanged shape — the new
  `visibility` column flows through `.select()` naturally; the
  screen does the grouping. Repo signature stays flat for now to
  minimise churn; can refactor to a typed `TieredDocuments`
  result later if multiple consumers need it.
- Demo data updated with one row of each tier so the layout
  exercises all three section headers.

### Ops doc
- New Part 7 in `docs/ops_admin_guide.md` with step-by-step
  recipes for uploading each tier via Supabase Studio (storage
  + DB insert SQL), gotchas, and rollback SQL.

## Trade-offs
- `project_id ON DELETE SET NULL` (not CASCADE) means a
  soft-deleted project's docs go silent in the app (RLS will
  not match a NULL project_id against `IN (...)`). Better than
  cascade-deleting historical documents; ops can re-attach them
  by editing `project_id` once a successor project is created.
- INSERT policy enforces investor-tier only. An ops-only Edge
  Function could later expose admin-uploaded common/project
  flows from a tools UI; for now Studio is the supported path.

## Open questions
- Original spec said "Part 9" of ops_admin_guide.md but the doc
  currently ends at Part 6. Numbered as Part 7 to stay
  sequential; orchestrator can renumber later if 7/8/9 are
  spoken for in a parallel branch.

## Files
- supabase/migrations/20260513020000_032_documents_tiering_schema.sql
- supabase/migrations/20260513030000_033_documents_tiering_rls.sql
- lib/features/documents/models/document.dart
- lib/features/documents/documents_screen.dart
- lib/core/mock/demo_data.dart
- docs/ops_admin_guide.md (Part 7)
