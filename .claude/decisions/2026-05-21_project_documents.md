# Project-level documents (single source, fan-out via RLS)

Date: 2026-05-25 (logged under 2026-05-21 cluster per repo convention)
Migration: `054_project_documents.sql`
Status: locked

## Problem

The Documents tab used the existing `public.documents` table for all
three tiers (`common`, `project`, `investor`). For project-scoped files
shared across N investors -- LLP agreement, brochure, quarterly report
-- ops had to either:

1. Insert N rows into `documents`, one per investor (N-row hack), or
2. Insert one row with `visibility = 'project'` and trust the layered
   RLS to fan out reads.

Path (1) does not scale and is brittle when allocations change.
Path (2) works for reads but mixes per-investor metadata
(`investor_id`, `file_size_kb`, `doc_type`, KYC restrictions) into a
table whose columns were designed around a single-investor concept.
The result is a schema that "kind of" supports shared docs by
overloading nullable columns. Adding any project-doc-specific field --
category, sort_order, public flag -- would pollute every per-investor
row.

## Decision

Add a sibling table `public.project_documents` whose contract is
*"one row per file shared across N investors"*. Keep the existing
`public.documents` table for per-investor files (KYC, contracts,
payout receipts) -- untouched.

```
project_documents
- id            uuid pk
- project_id    uuid -> projects(id)
- storage_path  text   (key inside arl-documents bucket)
- title         text
- category      text   (agreement | brochure | report | ...)
- uploaded_at   timestamptz default now()
- uploaded_by   uuid -> auth.users(id)
- is_public     boolean default false
- sort_order    int    default 0
```

RLS: SELECT allowed when `is_public = true` OR the calling user has
at least one non-deleted `investor_units` row with
`issued_units > 0` in `project_id`. INSERT/UPDATE/DELETE: service-role
only -- ops works the queue via Supabase Studio. No client policies.

Same storage bucket as per-investor docs (`arl-documents`); different
table. Signed URLs flow through the existing
`StorageHelper.signedUrlsForBucket` batch helper -- no new storage
client paths.

## When to use which table

| Use `project_documents`                  | Use `documents`                       |
|------------------------------------------|---------------------------------------|
| LLP agreement, brochure, quarterly report| KYC packet, signed contract, payout receipt |
| One file shared across N investors       | One file per investor                 |
| Public briefings (`is_public = true`)    | Investor-specific tier (`visibility = 'investor'`) |
| Future: category / sort_order grow here  | Future: existing tier system stays as-is |

The legacy `visibility = 'common'` / `visibility = 'project'` rows in
`documents` are not migrated -- they keep working via the existing
tier RLS until ops re-uploads them on the new path. New shared docs
go to `project_documents` from this point forward.

## Why not extend `documents`?

Considered. Rejected because:

1. **Column pollution.** The per-investor columns (`investor_id`,
   `file_size_kb`, `doc_type` enum, `zoho_file_id`) all become
   semantically nullable for shared docs. The check constraints on
   `doc_type` and the FK to `investors` would have to be relaxed.
2. **RLS gets fork-shaped.** The current `documents: tiered read`
   policy already does `OR (visibility = 'project' AND project_id IN
   ...)` -- adding a category pill, public flag, and sort_order
   behind that same OR makes the policy harder to reason about.
3. **The provider story is cleaner.** `myProjectDocuments()` returns
   a `List<ProjectDocument>` that the UI groups by `project_id`.
   Mixing it with `InvestorDocument` would require the UI to inspect
   `visibility` and switch behaviour at the row level.

## App-side surface

- `lib/features/documents/models/project_document.dart` -- model.
- `lib/core/repositories/documents_repository.dart` --
  `projectDocuments(id)` and `myProjectDocuments()` methods. Both
  batch-sign URLs via `StorageHelper.signedUrlsForBucket` and cache
  rows in Hive under `project_documents_<id>` /
  `project_documents_all`.
- `lib/features/documents/documents_provider.dart` -- adds
  `allProjectDocumentsProvider` (autoDispose) and
  `projectDocumentsProvider` (autoDispose family).
- `lib/features/documents/documents_screen.dart` -- now renders two
  sections: gold-bordered "PROJECT DOCUMENTS" chip (grouped by
  project with unit count) on top, sand-bordered "PERSONAL
  DOCUMENTS" chip (the existing tier accordion) below.
- `lib/features/projects/project_detail_screen.dart` -- adds a small
  horizontal row of up to 4 project doc cards + "View all" pill ->
  `/documents`. The section evaporates when the provider returns
  empty so the screen stays lean.

The in-app viewer (`DocumentViewerScreen`) is unchanged. Project doc
taps construct an `InvestorDocument` adapter (visibility=project,
projectId set) so the viewer does not have to know about two scopes.

## Test sequence

1. `flutter pub get && dart analyze lib`
2. Upload a sample PDF: Supabase Studio -> Storage -> `arl-documents`
   -> path `<project-slug>/<filename>.pdf`
3. Insert catalog row: Table Editor -> `project_documents` ->
   `(project_id, storage_path, title, category)`
4. Sign in as an investor with `issued_units > 0` in that project ->
   Documents tab -> confirm the row renders under "PROJECT
   DOCUMENTS" grouped under the project name.
5. Tap the row -> in-app viewer opens with screenshot prevention
   live.
6. Sign in as a different investor with no allocation in that
   project -> confirm the row does NOT render (RLS verified).
7. Open the project detail screen -> confirm the small horizontal
   "Project Documents" row also lists the doc, and "View all" pushes
   to `/documents`.

## Risks / known gaps

- No client-side upload path (by design). Ops uploads everything via
  Supabase Studio. A future `upload-project-doc` Edge Function could
  attach an `uploaded_by` automatically -- for now the column stays
  nullable.
- The "120 units" badge on the project group header sums issued
  units for the signed-in investor only -- not the project total.
  If product ever wants the project total (e.g. "12,000 / 12,000
  issued"), that is a small UI tweak, not a schema change.
- Soft-delete: project_documents has no `deleted_at`. To retract a
  doc, delete the row. The `ON DELETE CASCADE` from `projects(id)`
  is intentional -- if a project is hard-deleted, its docs go with
  it.
