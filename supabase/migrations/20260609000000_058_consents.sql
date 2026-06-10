-- ============================================================
-- MIGRATION 058 — DPDP consent audit log
--
-- Append-only record of every consent grant or withdrawal. Each action
-- is a new row; the latest row per (user_id, purpose) is the current
-- state. This lets us demonstrate, per DPDP, WHO consented to WHAT,
-- under WHICH document version, and WHEN — and provides the withdrawal
-- trail (withdrawal = a new row with granted=false).
--
-- Purposes:
--   terms / privacy        -> acceptance captured at onboarding (required)
--   marketing              -> optional, withdrawable from Profile -> Security
--   service_notifications  -> reserved for future granular control
--
-- Self-service: a user inserts/reads only their own rows (RLS). There is
-- no UPDATE/DELETE policy — the log is immutable for auditability.
-- ============================================================

create table if not exists public.consents (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  purpose     text not null check (purpose in ('terms','privacy','marketing','service_notifications')),
  granted     boolean not null,
  doc_version text,
  source      text not null default 'app',
  created_at  timestamptz not null default now()
);

comment on table public.consents is
  'DPDP consent audit log. Append-only; latest row per (user_id,purpose) is current state.';

create index if not exists consents_user_purpose_idx
  on public.consents (user_id, purpose, created_at desc);

alter table public.consents enable row level security;

drop policy if exists "consents: read own" on public.consents;
create policy "consents: read own"
  on public.consents
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "consents: insert own" on public.consents;
create policy "consents: insert own"
  on public.consents
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

-- Rollback:
--   drop table if exists public.consents;
