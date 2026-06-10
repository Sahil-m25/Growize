-- ============================================================
-- MIGRATION 062 — Performance: RLS initplan + FK indexes
--
-- Supabase performance advisors flagged:
--  * auth_rls_initplan on user_settings (3 policies) and login_events (2)
--    — auth.uid() was re-evaluated per row. Wrap in (select auth.uid())
--    so it is evaluated once per query.
--  * unindexed foreign keys: kyc_resubmissions.investor_id,
--    project_documents.uploaded_by — add covering indexes.
-- No behavioural change; query performance at scale only.
-- ============================================================

-- login_events
drop policy if exists "login_events: read own rows" on public.login_events;
create policy "login_events: read own rows" on public.login_events
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "login_events: insert own row" on public.login_events;
create policy "login_events: insert own row" on public.login_events
  for insert to authenticated with check (user_id = (select auth.uid()));

-- user_settings
drop policy if exists "user_settings: read own row" on public.user_settings;
create policy "user_settings: read own row" on public.user_settings
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "user_settings: insert own row" on public.user_settings;
create policy "user_settings: insert own row" on public.user_settings
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "user_settings: update own row" on public.user_settings;
create policy "user_settings: update own row" on public.user_settings
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- covering indexes for unindexed foreign keys
create index if not exists kyc_resubmissions_investor_id_idx on public.kyc_resubmissions (investor_id);
create index if not exists project_documents_uploaded_by_idx on public.project_documents (uploaded_by);
