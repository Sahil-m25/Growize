-- ============================================================
-- MIGRATION 059 — DPDP data-principal rights: nomination + erasure
--
-- nominees: the person a Data Principal nominates to exercise their
--   rights on death/incapacity (DPDP s.14). One per investor; the
--   investor manages their own row.
-- erasure_requests: a Data Principal's request to erase their data.
--   Captured for the ops team to process within the SLA, honouring the
--   statutory retention carve-out for KYC/financial records (PMLA /
--   Companies / IT). Append-only from the user side (insert/select own);
--   ops updates status via service_role.
--
-- investors.id == auth.uid() by design, so RLS scopes on investor_id.
-- ============================================================

create table if not exists public.nominees (
  id           uuid primary key default gen_random_uuid(),
  investor_id  uuid not null references public.investors(id) on delete cascade,
  name         text not null,
  relationship text,
  email        text,
  phone        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (investor_id)
);

create table if not exists public.erasure_requests (
  id           uuid primary key default gen_random_uuid(),
  investor_id  uuid not null references public.investors(id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending','in_progress','completed','rejected')),
  reason       text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  ops_note     text
);
create index if not exists erasure_requests_investor_idx
  on public.erasure_requests (investor_id, requested_at desc);

alter table public.nominees enable row level security;
alter table public.erasure_requests enable row level security;

-- nominees: the investor fully manages their own nominee.
drop policy if exists "nominees: manage own" on public.nominees;
create policy "nominees: manage own" on public.nominees
  for all to authenticated
  using (investor_id = (select auth.uid()))
  with check (investor_id = (select auth.uid()));

-- erasure_requests: investor can raise and view their own requests.
-- Status changes are performed by ops via service_role (bypasses RLS).
drop policy if exists "erasure: insert own" on public.erasure_requests;
create policy "erasure: insert own" on public.erasure_requests
  for insert to authenticated
  with check (investor_id = (select auth.uid()));

drop policy if exists "erasure: read own" on public.erasure_requests;
create policy "erasure: read own" on public.erasure_requests
  for select to authenticated
  using (investor_id = (select auth.uid()));

-- Rollback:
--   drop table if exists public.erasure_requests;
--   drop table if exists public.nominees;
