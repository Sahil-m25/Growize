-- 054_project_documents.sql
-- Project-level documents visible to any investor with a non-zero allocation
-- in the project. Single source of truth per document -- no N-row fan-out.
--
-- Distinct from the per-investor `documents` table which holds KYC,
-- contracts, payout receipts (one row per investor, RLS-scoped to
-- investor_id). This table holds LLP agreements, brochures, quarterly
-- reports etc. where N investors share a single file.

create table if not exists public.project_documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  storage_path text not null,
  title text not null,
  category text not null default 'general',
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid references auth.users(id),
  is_public boolean not null default false,
  sort_order int not null default 0
);

create index if not exists project_documents_project_id_idx
  on public.project_documents (project_id, sort_order, uploaded_at desc);

alter table public.project_documents enable row level security;

-- Investors can read project docs if (a) the doc is public OR (b) they
-- have at least one non-zero, non-deleted allocation row in this project.
-- Mirrors the existing investor-scoped RLS patterns on `documents` and
-- `project_updates`. Note: investor_units.investor_id == auth.uid()
-- directly (no investors.user_id indirection), matching the policy on
-- those sibling tables.
create policy "project_documents: investor read"
  on public.project_documents
  for select
  to authenticated
  using (
    is_public = true
    OR exists (
      select 1
      from public.investor_units u
      where u.project_id = project_documents.project_id
        and u.investor_id = (select auth.uid())
        and u.deleted_at is null
        and coalesce(u.issued_units, 0) > 0
    )
  );

-- No INSERT/UPDATE/DELETE policies for clients -- only service-role
-- inserts via Supabase Studio / admin tooling.

comment on table public.project_documents is
  'Project-level documents visible to all investors with non-zero allocation in the project. Single row per file. Distinct from the per-investor "documents" table which holds KYC, contracts, payout receipts.';

comment on column public.project_documents.category is
  'Loose category label. Suggested values: agreement, brochure, report, certification, financial, regulatory, update.';

comment on column public.project_documents.is_public is
  'If true, visible to ALL authenticated users regardless of allocation. Use sparingly -- e.g. for company-wide investor briefings.';
