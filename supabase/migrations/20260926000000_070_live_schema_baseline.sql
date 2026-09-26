-- =====================================================================
-- 070 — LIVE SCHEMA BASELINE (Growize Main DB, project oynfhdqizebvgmaoiuax)
-- =====================================================================
-- Extracted 2026-09-26 from the live database via read-only catalog
-- queries (pg_catalog / information_schema) through the Supabase
-- dashboard. This is the SOURCE OF TRUTH for the public schema.
--
-- Why: migrations_archive_20260608 + 058..069 had drifted from the live
-- DB (missing: get_portfolio_summary, llps, project_updates,
-- kyc_resubmissions, investors.roi_pct/date_of_birth/aadhaar_masked/
-- kyc_submitted_at, projects.llp_id/status/lat/lng, phase_copy,
-- auth_request_throttle, ...), so a fresh project could not be rebuilt.
--
-- How to use on a FRESH project: run this file alone (skip the older
-- migrations). On the existing project it is already applied - mark it
-- as applied with `supabase migration repair --status applied 20260926000000`.
--
-- NOT included (by design):
--   * Secrets. Cron jobs that call Edge Functions carry the service key /
--     cron secret in headers; they are listed as comments at the bottom.
--     Vault secret `cron_secret` must be created by hand.
--   * private.admin_emails (see section at the bottom).
--   * Known live defects are reproduced as-is so this file matches prod.
--     They are fixed separately in 071_security_and_trigger_fixes.sql.
-- =====================================================================

set check_function_bodies = off;
set client_min_messages = warning;

-- Extensions
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault with schema vault;
create extension if not exists "uuid-ossp" with schema extensions;

-- Private schema (admin allow-list used by public.is_admin()).
-- Column list reconstructed from is_admin(): `select email from private.admin_emails`.
create schema if not exists private;
create table if not exists private.admin_emails (
  email text primary key
);
revoke all on schema private from public, anon, authenticated;

-- Tables
create table if not exists public.app_config (
  key text not null,
  value text not null,
  updated_at timestamp with time zone default now()
);
create table if not exists public.app_releases (
  id uuid default gen_random_uuid() not null,
  version_code integer not null,
  version_name text not null,
  apk_url text,
  web_url text,
  release_notes text,
  is_critical boolean default false,
  created_at timestamp with time zone default now()
);
create table if not exists public.auth_request_throttle (
  bucket_key text not null,
  window_start timestamp with time zone default now() not null,
  hits integer default 0 not null
);
create table if not exists public.bank_change_requests (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  new_bank_name text,
  new_account_masked text,
  new_ifsc text,
  new_holder_name text,
  status text default 'pending'::text not null,
  notes text,
  requested_at timestamp with time zone default now(),
  resolved_at timestamp with time zone,
  updated_at timestamp with time zone default now() not null
);
create table if not exists public.consents (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  purpose text not null,
  granted boolean not null,
  doc_version text,
  source text default 'app'::text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.consultation_requests (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  project_id uuid not null,
  units_requested integer,
  message text,
  status text default 'new'::text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.crops (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  zoho_crop_id text,
  name text not null,
  emoji text default '🌱'::text,
  start_date date,
  end_date date,
  harvest_date date,
  progress_pct integer default 0 not null,
  is_current boolean default false not null,
  revenue numeric(14,2),
  updated_at timestamp with time zone default now()
);
create table if not exists public.documents (
  id uuid default gen_random_uuid() not null,
  investor_id uuid,
  project_id uuid,
  doc_type text default 'other'::text not null,
  name text not null,
  storage_path text not null,
  zoho_file_id text,
  file_size_kb integer,
  uploaded_at timestamp with time zone default now(),
  visibility text default 'investor'::text not null
);
create table if not exists public.erasure_requests (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  status text default 'pending'::text not null,
  reason text,
  requested_at timestamp with time zone default now() not null,
  processed_at timestamp with time zone,
  ops_note text
);
create table if not exists public.exit_requests (
  id uuid default gen_random_uuid() not null,
  investor_unit_id uuid not null,
  user_id uuid not null,
  reason text,
  status text default 'pending'::text not null,
  created_at timestamp with time zone default now() not null,
  resolved_at timestamp with time zone
);
create table if not exists public.gallery_photos (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  storage_path text not null,
  zoho_file_id text not null,
  caption text,
  unit_label text,
  taken_at date,
  uploaded_at timestamp with time zone default now()
);
create table if not exists public.investor_units (
  id uuid default gen_random_uuid() not null,
  zoho_allocation_id text,
  investor_id uuid not null,
  project_id uuid not null,
  issued_units integer default 0 not null,
  reserved_units integer default 0 not null,
  unit_price numeric(14,2),
  capital_invested numeric(14,2) default 0,
  capital_outstanding numeric(14,2) default 0,
  capital_returns numeric(14,2) default 0,
  total_amount_receivable numeric(14,2) default 0,
  total_amount_received numeric(14,2) default 0,
  token_advance_amount numeric(14,2) default 0,
  annual_yield_pct numeric(5,2),
  allocation_status text,
  customer_status text,
  investment_date date,
  next_payout_date date,
  updated_at timestamp with time zone default now(),
  last_synced_at timestamp with time zone,
  deleted_at timestamp with time zone
);
create table if not exists public.investors (
  id uuid not null,
  zoho_contact_id text,
  arl_id text,
  name text not null,
  email text not null,
  phone text,
  salutation text,
  kyc_status text default 'pending'::text not null,
  pan_masked text,
  bank_account_masked text,
  bank_ifsc text,
  bank_branch text,
  bank_holder_name text,
  bank_name text,
  address_line1 text,
  city text,
  state text,
  pincode text,
  country text,
  unit_allocated boolean default false,
  payment_received boolean default false,
  profile_verified boolean default false,
  agreement_signed boolean default false,
  fema_applicable boolean default false,
  onboarded_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  date_of_birth date,
  aadhaar_masked text,
  last_synced_at timestamp with time zone,
  deleted_at timestamp with time zone,
  kyc_submitted_at timestamp with time zone,
  roi_pct numeric(5,2) default 0 not null
);
create table if not exists public.kyc_resubmissions (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  investor_id uuid,
  reason text,
  pan_doc_url text,
  aadhaar_doc_url text,
  notes text,
  status text default 'pending'::text not null,
  created_at timestamp with time zone default now() not null
);
create table if not exists public.llps (
  id uuid default gen_random_uuid() not null,
  zoho_llp_id text,
  name text not null,
  llp_status text,
  llp_owner text,
  incorporation_no text,
  gst text,
  pan text,
  registered_address_line1 text,
  registered_city text,
  registered_state text,
  registered_pincode text,
  registered_country text,
  spoc1_name text,
  spoc1_phone text,
  spoc2_name text,
  spoc2_phone text,
  updated_at timestamp with time zone default now() not null,
  last_synced_at timestamp with time zone,
  deleted_at timestamp with time zone
);
create table if not exists public.login_events (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  occurred_at timestamp with time zone default now() not null,
  device_label text,
  platform text,
  app_version text,
  user_agent text
);
create table if not exists public.nominees (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  name text not null,
  relationship text,
  email text,
  phone text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);
create table if not exists public.notifications (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  type text not null,
  title text not null,
  body text,
  metadata jsonb default '{}'::jsonb not null,
  read_at timestamp with time zone,
  created_at timestamp with time zone default now()
);
create table if not exists public.payouts (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  project_id uuid not null,
  allocation_id uuid,
  source text default 'crm'::text not null,
  zoho_invoice_id text,
  amount numeric(14,2) not null,
  payout_date date,
  utr text,
  status text default 'pending'::text not null,
  crop_name text,
  notes text,
  idempotency_key text,
  updated_at timestamp with time zone default now(),
  is_demo boolean default false not null
);
create table if not exists public.phase_copy (
  stage_index integer not null,
  milestone_title text not null,
  started_body text not null,
  completed_body text not null,
  updated_at timestamp with time zone default now() not null
);
create table if not exists public.project_documents (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  storage_path text not null,
  title text not null,
  category text default 'general'::text not null,
  uploaded_at timestamp with time zone default now() not null,
  uploaded_by uuid,
  is_public boolean default false not null,
  sort_order integer default 0 not null,
  zoho_file_id text
);
create table if not exists public.project_phases (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  zoho_phase_id text,
  phase_name text not null,
  status text default 'pending'::text not null,
  phase_date date,
  sort_order integer default 0 not null,
  sub_items jsonb default '[]'::jsonb not null,
  updated_at timestamp with time zone default now(),
  image_url text,
  custom_title text,
  custom_body text
);
create table if not exists public.project_updates (
  id uuid default gen_random_uuid() not null,
  project_id uuid not null,
  update_date date not null,
  title text not null,
  body text not null,
  image_url text,
  created_at timestamp with time zone default now() not null,
  phase_id uuid,
  kind text
);
create table if not exists public.projects (
  id uuid default gen_random_uuid() not null,
  name text not null,
  tier text,
  status text,
  address_line1 text,
  city text,
  state text,
  pincode text,
  country text,
  total_units integer,
  units_issued integer default 0,
  units_available integer default 0,
  price_per_unit numeric(14,2),
  total_project_cost numeric(14,2),
  total_ticket_size numeric(14,2),
  acreage_acres numeric(10,2),
  annual_yield_pct numeric(5,2),
  launch_year date,
  insurance_provider text,
  insurance_policy_no text,
  insurance_expiry_date date,
  insured_amount numeric(14,2),
  cover_image_path text,
  color_hex text default '#1A2F24'::text not null,
  accent_hex text default '#2E7D6E'::text not null,
  updated_at timestamp with time zone default now(),
  is_listed_in_marketplace boolean default false,
  tagline text,
  subscription_deadline date,
  marketplace_image text,
  expected_annual_return_pct numeric,
  marketplace_sort_order integer default 100,
  llp_id uuid not null,
  last_synced_at timestamp with time zone,
  latitude double precision,
  longitude double precision,
  approx_radius_meters integer default 1500 not null,
  deleted_at timestamp with time zone
);
create table if not exists public.support_tickets (
  id uuid default gen_random_uuid() not null,
  investor_id uuid not null,
  project_id uuid,
  category text default 'general'::text not null,
  subject text not null,
  status text default 'open'::text not null,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);
create table if not exists public.sync_alerts (
  id uuid default gen_random_uuid() not null,
  table_name text not null,
  max_synced_at timestamp with time zone,
  age_seconds integer not null,
  threshold_secs integer not null,
  detail text,
  created_at timestamp with time zone default now()
);
create table if not exists public.ticket_messages (
  id uuid default gen_random_uuid() not null,
  ticket_id uuid not null,
  sender_type text not null,
  body text not null,
  created_at timestamp with time zone default now()
);
create table if not exists public.user_settings (
  user_id uuid not null,
  biometric_enabled boolean default false not null,
  notifications_enabled boolean default true not null,
  app_pin_hash text,
  app_pin_salt text,
  app_pin_iterations integer,
  updated_at timestamp with time zone default now() not null,
  terms_accepted_at timestamp with time zone,
  privacy_accepted_at timestamp with time zone
);
create table if not exists public.webhook_log (
  id uuid default gen_random_uuid() not null,
  source text not null,
  event_type text,
  zoho_record_id text,
  idempotency_key text,
  payload jsonb default '{}'::jsonb not null,
  status text default 'received'::text not null,
  error_message text,
  received_at timestamp with time zone default now(),
  processed_at timestamp with time zone
);

-- Primary keys, unique and check constraints
alter table public.app_config add constraint app_config_pkey PRIMARY KEY (key);
alter table public.app_releases add constraint app_releases_version_code_key UNIQUE (version_code);
alter table public.app_releases add constraint app_releases_pkey PRIMARY KEY (id);
alter table public.auth_request_throttle add constraint auth_request_throttle_pkey PRIMARY KEY (bucket_key);
alter table public.bank_change_requests add constraint bank_change_requests_pkey PRIMARY KEY (id);
alter table public.bank_change_requests add constraint bank_change_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.consents add constraint consents_pkey PRIMARY KEY (id);
alter table public.consents add constraint consents_purpose_check CHECK ((purpose = ANY (ARRAY['terms'::text, 'privacy'::text, 'marketing'::text, 'service_notifications'::text])));
alter table public.consultation_requests add constraint consultation_requests_pkey PRIMARY KEY (id);
alter table public.consultation_requests add constraint consultation_requests_status_check CHECK ((status = ANY (ARRAY['new'::text, 'contacted'::text, 'closed'::text])));
alter table public.crops add constraint crops_zoho_crop_id_key UNIQUE (zoho_crop_id);
alter table public.crops add constraint crops_pkey PRIMARY KEY (id);
alter table public.crops add constraint crops_progress_pct_check CHECK (((progress_pct >= 0) AND (progress_pct <= 100)));
alter table public.documents add constraint documents_zoho_file_id_key UNIQUE (zoho_file_id);
alter table public.documents add constraint documents_pkey PRIMARY KEY (id);
alter table public.documents add constraint documents_doc_type_check CHECK ((doc_type = ANY (ARRAY['contract'::text, 'agreement'::text, 'kyc'::text, 'other'::text])));
alter table public.documents add constraint documents_storage_path_no_bucket_prefix CHECK ((storage_path !~~ 'documents/%'::text));
alter table public.documents add constraint documents_tier_columns_check CHECK ((((visibility = 'common'::text) AND (investor_id IS NULL) AND (project_id IS NULL)) OR ((visibility = 'project'::text) AND (investor_id IS NULL) AND (project_id IS NOT NULL)) OR ((visibility = 'investor'::text) AND (investor_id IS NOT NULL))));
alter table public.documents add constraint documents_visibility_check CHECK ((visibility = ANY (ARRAY['common'::text, 'project'::text, 'investor'::text])));
alter table public.erasure_requests add constraint erasure_requests_pkey PRIMARY KEY (id);
alter table public.erasure_requests add constraint erasure_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'rejected'::text])));
alter table public.exit_requests add constraint exit_requests_pkey PRIMARY KEY (id);
alter table public.exit_requests add constraint exit_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'settled'::text])));
alter table public.gallery_photos add constraint gallery_photos_zoho_file_id_key UNIQUE (zoho_file_id);
alter table public.gallery_photos add constraint gallery_photos_pkey PRIMARY KEY (id);
alter table public.investor_units add constraint investor_units_zoho_allocation_id_key UNIQUE (zoho_allocation_id);
alter table public.investor_units add constraint investor_units_pkey PRIMARY KEY (id);
alter table public.investors add constraint investors_arl_id_key UNIQUE (arl_id);
alter table public.investors add constraint investors_email_key UNIQUE (email);
alter table public.investors add constraint investors_zoho_contact_id_key UNIQUE (zoho_contact_id);
alter table public.investors add constraint investors_pkey PRIMARY KEY (id);
alter table public.investors add constraint investors_kyc_status_check CHECK ((kyc_status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'verified'::text, 'rejected'::text])));
alter table public.kyc_resubmissions add constraint kyc_resubmissions_pkey PRIMARY KEY (id);
alter table public.kyc_resubmissions add constraint kyc_resubmissions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_review'::text, 'accepted'::text, 'rejected'::text])));
alter table public.llps add constraint llps_zoho_llp_id_key UNIQUE (zoho_llp_id);
alter table public.llps add constraint llps_pkey PRIMARY KEY (id);
alter table public.login_events add constraint login_events_pkey PRIMARY KEY (id);
alter table public.nominees add constraint nominees_investor_id_key UNIQUE (investor_id);
alter table public.nominees add constraint nominees_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_type_check CHECK ((type = ANY (ARRAY['payout'::text, 'photo'::text, 'ticket'::text, 'reminder'::text, 'milestone'::text, 'kyc'::text, 'exit'::text, 'bank_change'::text, 'phase_update'::text, 'document'::text, 'new_project'::text])));
alter table public.payouts add constraint payouts_idempotency_key_key UNIQUE (idempotency_key);
alter table public.payouts add constraint payouts_zoho_invoice_id_key UNIQUE (zoho_invoice_id);
alter table public.payouts add constraint payouts_pkey PRIMARY KEY (id);
alter table public.payouts add constraint payouts_source_check CHECK ((source = ANY (ARRAY['crm'::text, 'books'::text, 'manual'::text])));
alter table public.payouts add constraint payouts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processed'::text, 'on_hold'::text])));
alter table public.phase_copy add constraint phase_copy_pkey PRIMARY KEY (stage_index);
alter table public.phase_copy add constraint phase_copy_stage_index_check CHECK (((stage_index >= 0) AND (stage_index <= 9)));
alter table public.project_documents add constraint project_documents_zoho_file_id_key UNIQUE (zoho_file_id);
alter table public.project_documents add constraint project_documents_pkey PRIMARY KEY (id);
alter table public.project_phases add constraint project_phases_zoho_phase_id_key UNIQUE (zoho_phase_id);
alter table public.project_phases add constraint project_phases_pkey PRIMARY KEY (id);
alter table public.project_phases add constraint project_phases_status_check CHECK ((status = ANY (ARRAY['done'::text, 'current'::text, 'pending'::text])));
alter table public.project_updates add constraint project_updates_pkey PRIMARY KEY (id);
alter table public.projects add constraint projects_pkey PRIMARY KEY (id);
alter table public.projects add constraint projects_approx_radius_range CHECK (((approx_radius_meters >= 250) AND (approx_radius_meters <= 20000)));
alter table public.projects add constraint projects_lat_range CHECK (((latitude IS NULL) OR ((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))));
alter table public.projects add constraint projects_lng_range CHECK (((longitude IS NULL) OR ((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))));
alter table public.projects add constraint projects_units_nonneg CHECK (((units_available >= 0) AND (units_issued >= 0) AND (units_issued <= COALESCE(total_units, units_issued))));
alter table public.support_tickets add constraint support_tickets_pkey PRIMARY KEY (id);
alter table public.support_tickets add constraint support_tickets_category_check CHECK ((category = ANY (ARRAY['payout'::text, 'documents'::text, 'general'::text, 'bank_change'::text, 'exit_request'::text])));
alter table public.support_tickets add constraint support_tickets_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text])));
alter table public.sync_alerts add constraint sync_alerts_pkey PRIMARY KEY (id);
alter table public.ticket_messages add constraint ticket_messages_pkey PRIMARY KEY (id);
alter table public.ticket_messages add constraint ticket_messages_sender_type_check CHECK ((sender_type = ANY (ARRAY['investor'::text, 'staff'::text])));
alter table public.user_settings add constraint user_settings_pkey PRIMARY KEY (user_id);
alter table public.webhook_log add constraint webhook_log_idempotency_key_key UNIQUE (idempotency_key);
alter table public.webhook_log add constraint webhook_log_pkey PRIMARY KEY (id);
alter table public.webhook_log add constraint webhook_log_source_check CHECK ((source = ANY (ARRAY['zoho_crm'::text, 'zoho_books'::text, 'gallery_sync'::text, 'documents_sync'::text, 'manual'::text])));
alter table public.webhook_log add constraint webhook_log_status_check CHECK ((status = ANY (ARRAY['received'::text, 'processed'::text, 'failed'::text, 'duplicate'::text])));

-- Foreign keys
alter table public.bank_change_requests add constraint bank_change_requests_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.consents add constraint consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.consultation_requests add constraint consultation_requests_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.consultation_requests add constraint consultation_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crops add constraint crops_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.documents add constraint documents_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.documents add constraint documents_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL;
alter table public.erasure_requests add constraint erasure_requests_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.exit_requests add constraint exit_requests_investor_unit_id_fkey FOREIGN KEY (investor_unit_id) REFERENCES investor_units(id) ON DELETE CASCADE;
alter table public.exit_requests add constraint exit_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.gallery_photos add constraint gallery_photos_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.investor_units add constraint investor_units_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.investor_units add constraint investor_units_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.investors add constraint investors_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.kyc_resubmissions add constraint kyc_resubmissions_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.kyc_resubmissions add constraint kyc_resubmissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.login_events add constraint login_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.nominees add constraint nominees_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.notifications add constraint notifications_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.payouts add constraint payouts_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES investor_units(id) ON DELETE SET NULL;
alter table public.payouts add constraint payouts_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.payouts add constraint payouts_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.project_documents add constraint project_documents_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.project_documents add constraint project_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id);
alter table public.project_phases add constraint project_phases_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.project_updates add constraint project_updates_phase_id_fkey FOREIGN KEY (phase_id) REFERENCES project_phases(id) ON DELETE SET NULL;
alter table public.project_updates add constraint project_updates_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
alter table public.projects add constraint projects_llp_id_fkey FOREIGN KEY (llp_id) REFERENCES llps(id) ON DELETE CASCADE;
alter table public.support_tickets add constraint support_tickets_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES investors(id) ON DELETE CASCADE;
alter table public.support_tickets add constraint support_tickets_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL;
alter table public.ticket_messages add constraint ticket_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES support_tickets(id) ON DELETE CASCADE;
alter table public.user_settings add constraint user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_auth_throttle_window ON public.auth_request_throttle USING btree (window_start);
CREATE INDEX IF NOT EXISTS idx_bank_change_requests_investor_id ON public.bank_change_requests USING btree (investor_id);
CREATE INDEX IF NOT EXISTS consents_user_purpose_idx ON public.consents USING btree (user_id, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_consultation_project_status ON public.consultation_requests USING btree (project_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_consultation_user_created ON public.consultation_requests USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crops_one_current_per_project ON public.crops USING btree (project_id) WHERE (is_current = true);
CREATE INDEX IF NOT EXISTS idx_documents_investor ON public.documents USING btree (investor_id, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_project ON public.documents USING btree (project_id, uploaded_at DESC) WHERE (project_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_documents_project_id ON public.documents USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_documents_visibility ON public.documents USING btree (visibility, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS erasure_requests_investor_idx ON public.erasure_requests USING btree (investor_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_exit_requests_user_created ON public.exit_requests USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_exit_requests_pending_unit ON public.exit_requests USING btree (investor_unit_id) WHERE (status = 'pending'::text);
CREATE INDEX IF NOT EXISTS idx_gallery_project_uploaded ON public.gallery_photos USING btree (project_id, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_investor_units_deleted_at ON public.investor_units USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_investor_units_investor_id ON public.investor_units USING btree (investor_id);
CREATE INDEX IF NOT EXISTS idx_investor_units_last_synced_at ON public.investor_units USING btree (last_synced_at DESC);
CREATE INDEX IF NOT EXISTS idx_investor_units_project_id ON public.investor_units USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_investors_deleted_at ON public.investors USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_investors_last_synced_at ON public.investors USING btree (last_synced_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS investors_zoho_contact_id_unique ON public.investors USING btree (zoho_contact_id) WHERE (zoho_contact_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_kyc_resub_status_created ON public.kyc_resubmissions USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kyc_resub_user_created ON public.kyc_resubmissions USING btree (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS kyc_resubmissions_investor_id_idx ON public.kyc_resubmissions USING btree (investor_id);
CREATE INDEX IF NOT EXISTS idx_llps_deleted_at ON public.llps USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_llps_last_synced_at ON public.llps USING btree (last_synced_at DESC);
CREATE INDEX IF NOT EXISTS idx_llps_zoho_llp_id ON public.llps USING btree (zoho_llp_id);
CREATE INDEX IF NOT EXISTS idx_login_events_user_time ON public.login_events USING btree (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_investor_unread ON public.notifications USING btree (investor_id, created_at DESC) WHERE (read_at IS NULL);
CREATE INDEX IF NOT EXISTS idx_notifications_phase_update_dedupe ON public.notifications USING btree (investor_id, ((metadata ->> 'project_id'::text)), ((metadata ->> 'stage_index'::text)), ((metadata ->> 'kind'::text))) WHERE (type = 'phase_update'::text);
CREATE INDEX IF NOT EXISTS idx_payouts_allocation_id ON public.payouts USING btree (allocation_id);
CREATE INDEX IF NOT EXISTS idx_payouts_investor_date ON public.payouts USING btree (investor_id, payout_date DESC);
CREATE INDEX IF NOT EXISTS idx_payouts_project ON public.payouts USING btree (project_id);
CREATE INDEX IF NOT EXISTS project_documents_project_id_idx ON public.project_documents USING btree (project_id, sort_order, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS project_documents_uploaded_by_idx ON public.project_documents USING btree (uploaded_by);
CREATE INDEX IF NOT EXISTS idx_phases_project_order ON public.project_phases USING btree (project_id, sort_order);
CREATE INDEX IF NOT EXISTS project_updates_project_date_idx ON public.project_updates USING btree (project_id, update_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_project_updates_phase_kind ON public.project_updates USING btree (phase_id, kind) WHERE (phase_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_projects_deleted_at ON public.projects USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_projects_last_synced_at ON public.projects USING btree (last_synced_at DESC);
CREATE INDEX IF NOT EXISTS idx_projects_llp_id ON public.projects USING btree (llp_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_project_id ON public.support_tickets USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_tickets_investor_status ON public.support_tickets USING btree (investor_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_alerts_created ON public.sync_alerts USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ticket_messages_ticket ON public.ticket_messages USING btree (ticket_id, created_at);
CREATE INDEX IF NOT EXISTS idx_webhook_log_source_received ON public.webhook_log USING btree (source, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_log_status ON public.webhook_log USING btree (status) WHERE (status = 'failed'::text);

-- Functions
CREATE OR REPLACE FUNCTION public.broadcast_new_project_notification(p_project_id uuid, p_project_name text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  inserted_count integer;
BEGIN
  WITH ins AS (
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    SELECT DISTINCT
      iu.investor_id,
      'new_project',
      'New project available',
      'A new project — ' || COALESCE(p_project_name, 'untitled') ||
        ' — is open for reservation. Tap to explore.',
      jsonb_build_object(
        'project_id', p_project_id,
        'project_name', p_project_name
      )
    FROM public.investor_units iu
    WHERE iu.deleted_at IS NULL
      AND iu.investor_id IS NOT NULL
    RETURNING 1
  )
  SELECT COUNT(*) INTO inserted_count FROM ins;
  RETURN COALESCE(inserted_count, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.broadcast_phase_update_notification(p_project_id uuid, p_phase_name text, p_project_name text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  inserted_count integer;
BEGIN
  WITH ins AS (
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    SELECT DISTINCT
      iu.investor_id,
      'phase_update',
      'Phase update: ' || COALESCE(p_phase_name, 'phase change'),
      COALESCE(p_project_name, 'Your project') || ' is now in ' ||
        COALESCE(p_phase_name, 'a new phase') || '.',
      jsonb_build_object(
        'project_id', p_project_id,
        'phase_name', p_phase_name,
        'project_name', p_project_name
      )
    FROM public.investor_units iu
    WHERE iu.project_id = p_project_id
      AND iu.deleted_at IS NULL
      AND iu.investor_id IS NOT NULL
    RETURNING 1
  )
  SELECT COUNT(*) INTO inserted_count FROM ins;
  RETURN COALESCE(inserted_count, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_auth_throttle(p_key text, p_limit integer DEFAULT 3, p_window_secs integer DEFAULT 900)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hits   INTEGER;
  v_window INTERVAL := make_interval(secs => p_window_secs);
BEGIN
  -- Opportunistic cleanup, ~2% of calls, so the table cannot grow forever
  -- without paying for a scan on every single request.
  IF random() < 0.02 THEN
    DELETE FROM public.auth_request_throttle
     WHERE window_start < now() - v_window - INTERVAL '1 hour';
  END IF;

  INSERT INTO public.auth_request_throttle AS t (bucket_key, window_start, hits)
  VALUES (p_key, now(), 1)
  ON CONFLICT (bucket_key) DO UPDATE
    SET hits = CASE WHEN t.window_start < now() - v_window THEN 1
                    ELSE t.hits + 1 END,
        window_start = CASE WHEN t.window_start < now() - v_window THEN now()
                            ELSE t.window_start END
  RETURNING t.hits INTO v_hits;

  RETURN v_hits <= p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_summary()
 RETURNS TABLE(investor_id uuid, project_count bigint, total_units numeric, total_invested numeric, total_capital_received numeric, total_capital_outstanding numeric, total_payouts_received numeric, roi_pct numeric, avg_annual_yield_pct numeric, next_payout_date date, next_payout_amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    WITH iu_agg AS (
        SELECT
            iu.investor_id,
            count(DISTINCT iu.project_id)              AS project_count,
            sum(iu.issued_units)                       AS total_units,
            COALESCE(sum(iu.capital_invested),     0)  AS sum_capital_invested,
            COALESCE(sum(iu.token_advance_amount), 0)  AS sum_token,
            COALESCE(sum(iu.total_amount_received),0)  AS sum_total_received,
            COALESCE(sum(iu.capital_outstanding),  0)  AS sum_outstanding,
            avg(iu.annual_yield_pct)                   AS avg_annual_yield_pct
        FROM investor_units iu
        WHERE iu.investor_id = auth.uid()
          AND iu.deleted_at IS NULL
        GROUP BY iu.investor_id
    ),
    p_agg AS (
        SELECT
            p.investor_id,
            COALESCE(sum(p.amount) FILTER (
                WHERE p.status = 'processed' AND p.is_demo = false
            ), 0) AS sum_received,
            min(p.payout_date) FILTER (
                WHERE p.status = 'pending' AND p.is_demo = false
            ) AS next_pending_date
        FROM payouts p
        WHERE p.investor_id = auth.uid()
        GROUP BY p.investor_id
    )
    SELECT
        iu.investor_id,
        iu.project_count,
        iu.total_units,
        iu.sum_capital_invested + iu.sum_token          AS total_invested,
        iu.sum_total_received                           AS total_capital_received,
        iu.sum_outstanding                              AS total_capital_outstanding,
        COALESCE(p.sum_received, 0)                     AS total_payouts_received,
        CASE
            WHEN (iu.sum_capital_invested + iu.sum_token) > 0 THEN
                round(COALESCE(p.sum_received, 0) / (iu.sum_capital_invested + iu.sum_token) * 100, 2)
            ELSE 0
        END                                             AS roi_pct,
        iu.avg_annual_yield_pct,
        p.next_pending_date                             AS next_payout_date,
        (
            SELECT py.amount
            FROM payouts py
            WHERE py.investor_id = auth.uid()
              AND py.status = 'pending'
              AND py.is_demo = false
            ORDER BY py.payout_date
            LIMIT 1
        )                                               AS next_payout_amount
    FROM iu_agg iu
    LEFT JOIN p_agg p ON p.investor_id = iu.investor_id;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  select coalesce(lower(auth.jwt() ->> 'email') in (select email from private.admin_emails), false)
      or coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$function$;

CREATE OR REPLACE FUNCTION public.notify_bank_change_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_title TEXT; v_body TEXT;
BEGIN
  IF OLD.status = 'pending'
     AND NEW.status IN ('approved', 'rejected')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'approved' THEN
      v_title := 'Bank change approved';
      v_body := 'Your bank account update has been approved and will reflect after the next CRM sync.';
    ELSE
      v_title := 'Bank change rejected';
      v_body := COALESCE('Your bank account update was rejected. ' || NEW.notes,
                         'Your bank account update was rejected. Contact support for details.');
    END IF;
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.investor_id, 'bank_change', v_title, v_body,
      jsonb_build_object('bank_change_request_id', NEW.id, 'status', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_consultation_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_temp'
AS $function$
DECLARE v_secret TEXT;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'cron_secret';
  IF v_secret IS NULL THEN
    RAISE WARNING 'cron_secret not in vault; skipping Slack notify for consultation %', NEW.id;
    RETURN NEW;
  END IF;
  PERFORM net.http_post(
    url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/notify-consultation-request',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-arl-cron-secret', v_secret),
    body := jsonb_build_object('consultation_request_id', NEW.id)
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_document_uploaded()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
BEGIN
  v_title := 'New document available';
  v_body := 'A new document "' || COALESCE(NEW.name, 'untitled') || '" is now available to view.';

  IF NEW.visibility = 'investor' THEN
    IF NEW.investor_id IS NULL THEN
      RETURN NEW;
    END IF;
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.investor_id,
      'document',
      v_title,
      v_body,
      jsonb_build_object(
        'document_id', NEW.id,
        'doc_type', NEW.doc_type,
        'visibility', NEW.visibility
      )
    );
  ELSIF NEW.visibility = 'project' THEN
    IF NEW.project_id IS NULL THEN
      RETURN NEW;
    END IF;
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    SELECT DISTINCT
      iu.investor_id,
      'document',
      v_title,
      v_body,
      jsonb_build_object(
        'document_id', NEW.id,
        'doc_type', NEW.doc_type,
        'visibility', NEW.visibility,
        'project_id', NEW.project_id
      )
    FROM public.investor_units iu
    WHERE iu.project_id = NEW.project_id
      AND iu.deleted_at IS NULL
      AND iu.investor_id IS NOT NULL;
  ELSIF NEW.visibility = 'common' THEN
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    SELECT DISTINCT
      iu.investor_id,
      'document',
      v_title,
      v_body,
      jsonb_build_object(
        'document_id', NEW.id,
        'doc_type', NEW.doc_type,
        'visibility', NEW.visibility
      )
    FROM public.investor_units iu
    WHERE iu.deleted_at IS NULL
      AND iu.investor_id IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_exit_request_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_title TEXT; v_body TEXT;
BEGIN
  -- Fire for any transition INTO a terminal state, regardless
  -- of the prior state. Handles pending -> approved -> settled.
  IF NEW.status IN ('approved', 'rejected', 'settled')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'approved' THEN v_title := 'Exit request approved'; v_body := 'Your exit request has been approved. Settlement will follow.';
      WHEN 'rejected' THEN v_title := 'Exit request rejected'; v_body := 'Your exit request has been rejected. Reach out to support for details.';
      ELSE                  v_title := 'Exit settled';         v_body := 'Your exit settlement has been processed.';
    END CASE;
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.user_id, 'exit', v_title, v_body,
      jsonb_build_object('exit_request_id', NEW.id, 'status', NEW.status, 'investor_unit_id', NEW.investor_unit_id)
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_investor_kyc_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.kyc_status = 'pending'
     AND NEW.kyc_status IN ('verified', 'rejected')
     AND NEW.kyc_status IS DISTINCT FROM OLD.kyc_status THEN
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.id,
      'kyc',
      CASE WHEN NEW.kyc_status = 'verified' THEN 'KYC verified' ELSE 'KYC rejected' END,
      CASE WHEN NEW.kyc_status = 'verified'
           THEN 'Your KYC has been verified. Tap to view.'
           ELSE 'Your KYC has been rejected. Please re-submit.' END,
      jsonb_build_object('kyc_status', NEW.kyc_status, 'previous_status', OLD.kyc_status)
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_kyc_resubmission_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    DECLARE v_title TEXT; v_body TEXT;
    BEGIN
      IF NEW.status IN ('accepted', 'rejected') AND NEW.status IS DISTINCT FROM OLD.status THEN
        CASE NEW.status
          WHEN 'accepted' THEN
            v_title := 'KYC re-submission accepted';
            v_body := 'Your KYC re-submission has been accepted.';
          ELSE
            v_title := 'KYC re-submission rejected';
            v_body := 'Your KYC re-submission has been rejected. Please review and re-submit.';
        END CASE;
        INSERT INTO public.notifications (investor_id, type, title, body, metadata)
        VALUES (NEW.investor_id, 'kyc', v_title, v_body,
          jsonb_build_object('kyc_resubmission_id', NEW.id, 'status', NEW.status, 'previous_status', OLD.status));
      END IF;
      RETURN NEW;
    END;
    $function$;

-- NOTE: live definition reproduced as-is. `NEW.is_demo` does not exist on
-- project_phases, so this raises on every stage change -> fixed in 071.
CREATE OR REPLACE FUNCTION public.notify_project_phase_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kind TEXT; v_project_name TEXT;
  v_title TEXT; v_body TEXT; v_meta JSONB; v_notified INT;
BEGIN
  IF NEW.status = 'current'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'current') THEN
    v_kind := 'started';
  ELSIF NEW.status = 'done' AND TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM 'done' THEN
    v_kind := 'completed';   -- BACKFILL GUARD: UPDATE only, never INSERT
  ELSE
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.is_demo, FALSE) THEN RETURN NEW; END IF;

  SELECT p.name INTO v_project_name FROM public.projects p
  WHERE p.id = NEW.project_id AND p.deleted_at IS NULL;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT r.title, r.body INTO v_title, v_body
    FROM public.resolve_phase_copy(NEW::public.project_phases, v_kind, v_project_name) r;

  v_meta := jsonb_build_object(
    'project_id', NEW.project_id, 'project_name', v_project_name,
    'stage_index', NEW.sort_order, 'phase_name', NEW.phase_name,
    'kind', v_kind,
    'cta_route', '/projects/' || NEW.project_id::TEXT,
    'cta_label', 'View Project');

  IF NEW.image_url IS NOT NULL AND TRIM(NEW.image_url) <> '' THEN
    v_meta := v_meta || jsonb_build_object('image_url', NEW.image_url);
  END IF;

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT DISTINCT iu.investor_id, 'phase_update', v_title, v_body, v_meta
  FROM public.investor_units iu
  LEFT JOIN public.user_settings us ON us.user_id = iu.investor_id
  WHERE iu.project_id = NEW.project_id
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.investor_id = iu.investor_id AND n.type = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
        AND n.metadata ->> 'kind'        = v_kind);
  GET DIAGNOSTICS v_notified = ROW_COUNT;

  -- The durable copy. Unlike the notification this is not per-investor and
  -- never expires.
  PERFORM public.upsert_phase_project_update(
            NEW::public.project_phases, v_kind, v_title, v_body);

  RAISE LOG 'notify_project_phase_change: project=% stage=% kind=% notified=%',
            NEW.project_id, NEW.sort_order, v_kind, v_notified;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.notify_ticket_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_investor_id UUID; v_short_id TEXT; v_is_first BOOLEAN; v_title TEXT; v_body TEXT;
BEGIN
  IF NEW.sender_type = 'investor' THEN RETURN NEW; END IF;
  SELECT investor_id INTO v_investor_id FROM public.support_tickets WHERE id = NEW.ticket_id;
  IF v_investor_id IS NULL THEN RETURN NEW; END IF;
  v_short_id := substr(NEW.ticket_id::text, 1, 8);
  SELECT NOT EXISTS (
    SELECT 1 FROM public.ticket_messages WHERE ticket_id = NEW.ticket_id AND id <> NEW.id
  ) INTO v_is_first;
  IF v_is_first THEN
    v_title := 'New message from ARL';
    v_body := 'A new ticket #' || v_short_id || ' has been opened by ARL support.';
  ELSE
    v_title := 'New reply on your ticket';
    v_body := 'New reply on ticket #' || v_short_id || '.';
  END IF;
  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  VALUES (v_investor_id, 'ticket', v_title, v_body,
    jsonb_build_object('ticket_id', NEW.ticket_id, 'message_id', NEW.id, 'sender_type', NEW.sender_type, 'is_first', v_is_first));
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.purge_expired_personal_data()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.login_events
    where occurred_at < now() - interval '18 months';
  delete from public.notifications
    where created_at < now() - interval '12 months';
  delete from public.consultation_requests
    where created_at < now() - interval '24 months';
end;
$function$;

CREATE OR REPLACE FUNCTION public.recompute_project_units(p_project_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_issued NUMERIC; v_total NUMERIC;
BEGIN
  IF p_project_id IS NULL THEN RETURN; END IF;
  SELECT COALESCE(SUM(issued_units), 0) INTO v_issued
    FROM public.investor_units
   WHERE project_id = p_project_id AND deleted_at IS NULL AND allocation_status = 'Issued';
  SELECT COALESCE(total_units, 0) INTO v_total FROM public.projects WHERE id = p_project_id;
  UPDATE public.projects
     SET units_issued = v_issued,
         units_available = GREATEST(v_total - v_issued, 0)
   WHERE id = p_project_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_phase_copy(p_phase project_phases, p_kind text, p_project_name text)
 RETURNS TABLE(title text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_copy public.phase_copy%ROWTYPE; v_label TEXT; v_title TEXT; v_body TEXT;
BEGIN
  v_label := COALESCE(NULLIF(TRIM(p_phase.phase_name), ''), 'a new stage');
  SELECT * INTO v_copy FROM public.phase_copy WHERE stage_index = p_phase.sort_order;
  IF FOUND THEN
    v_title := v_copy.milestone_title;
    v_body  := CASE WHEN p_kind='started' THEN v_copy.started_body ELSE v_copy.completed_body END;
  ELSE
    IF p_kind='started' THEN
      v_title := 'Stage update: ' || v_label;
      v_body  := '{project} has moved to ' || v_label || '.';
    ELSE
      v_title := 'Stage complete: ' || v_label;
      v_body  := '{project} has completed the ' || v_label || ' stage.';
    END IF;
  END IF;
  IF p_phase.custom_title IS NOT NULL AND TRIM(p_phase.custom_title) <> '' THEN
    v_title := p_phase.custom_title; END IF;
  IF p_phase.custom_body IS NOT NULL AND TRIM(p_phase.custom_body) <> '' THEN
    v_body := p_phase.custom_body; END IF;
  RETURN QUERY SELECT v_title,
    REPLACE(v_body,'{project}',COALESCE(p_project_name,'Your project'));
END $function$;

CREATE OR REPLACE FUNCTION public.set_kyc_submitted_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.kyc_status IN ('in_progress', 'verified')
     AND (OLD.kyc_status IS DISTINCT FROM NEW.kyc_status)
     AND NEW.kyc_submitted_at IS NULL THEN
    NEW.kyc_submitted_at = now();
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_investor_phone_to_auth()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_phone text;
BEGIN
  IF NEW.phone IS DISTINCT FROM OLD.phone THEN
    v_phone := CASE
                 WHEN NEW.phone IS NULL THEN NULL
                 ELSE regexp_replace(NEW.phone, '^\+', '')
               END;

    -- If another auth user already owns this phone, don't fight the
    -- UNIQUE(phone) constraint — skip the sync rather than abort the
    -- whole investors write.
    IF v_phone IS NOT NULL AND EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.phone = v_phone AND u.id <> NEW.id
    ) THEN
      RAISE NOTICE 'sync_investor_phone_to_auth: phone % already owned by another auth user; leaving auth.users.phone NULL for investor %', v_phone, NEW.id;
      RETURN NEW;
    END IF;

    -- Belt-and-suspenders: even if a race slips past the check above,
    -- swallow the unique violation instead of rolling back onboarding.
    BEGIN
      UPDATE auth.users
      SET phone = v_phone,
          updated_at = now()
      WHERE id = NEW.id;
    EXCEPTION WHEN unique_violation THEN
      RAISE NOTICE 'sync_investor_phone_to_auth: unique_violation writing phone % for investor %; skipped', v_phone, NEW.id;
    END;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_phase_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_project_name TEXT; v_kind TEXT; v_title TEXT; v_body TEXT;
  v_total INT := 0; v_n INT;
BEGIN
  SELECT p.name INTO v_project_name FROM public.projects p
   WHERE p.id = NEW.project_id AND p.deleted_at IS NULL;
  IF NOT FOUND THEN RETURN NEW; END IF;

  FOREACH v_kind IN ARRAY ARRAY['started','completed'] LOOP
    SELECT r.title, r.body INTO v_title, v_body
      FROM public.resolve_phase_copy(NEW::public.project_phases, v_kind, v_project_name) r;

    UPDATE public.notifications n
       SET title = v_title,
           body  = v_body,
           metadata = CASE
             WHEN NEW.image_url IS NOT NULL AND TRIM(NEW.image_url) <> ''
               THEN n.metadata || jsonb_build_object('image_url', NEW.image_url)
             ELSE n.metadata - 'image_url'
           END
     WHERE n.type = 'phase_update'
       AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
       AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
       AND n.metadata ->> 'kind'        = v_kind;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;

    -- Only touch an update that already exists; an edit must not create a
    -- narrative post for a milestone that never fired.
    IF EXISTS (SELECT 1 FROM public.project_updates
                WHERE phase_id = NEW.id AND kind = v_kind) THEN
      PERFORM public.upsert_phase_project_update(
                NEW::public.project_phases, v_kind, v_title, v_body);
    END IF;
  END LOOP;

  RAISE LOG 'sync_phase_notifications: project=% stage=% updated=%',
            NEW.project_id, NEW.sort_order, v_total;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.trg_recompute_project_units_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_project_units(OLD.project_id);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' AND OLD.project_id IS DISTINCT FROM NEW.project_id THEN
    PERFORM public.recompute_project_units(OLD.project_id);
    PERFORM public.recompute_project_units(NEW.project_id);
    RETURN NEW;
  ELSE
    PERFORM public.recompute_project_units(NEW.project_id);
    RETURN NEW;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when s ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then s::uuid
    else null
  end
  from (
    select coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ) as s
  ) q
$function$;

CREATE OR REPLACE FUNCTION public.upsert_phase_project_update(p_phase project_phases, p_kind text, p_title text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.project_updates AS u
    (project_id, update_date, title, body, image_url, phase_id, kind)
  VALUES (
    p_phase.project_id,
    -- Prefer the real milestone date. CURRENT_DATE is a fallback, not a
    -- guess dressed up as fact: set project_phases.phase_date and the
    -- update re-dates itself.
    COALESCE(p_phase.phase_date, CURRENT_DATE),
    p_title,
    p_body,
    NULLIF(TRIM(COALESCE(p_phase.image_url, '')), ''),
    p_phase.id,
    p_kind
  )
  ON CONFLICT (phase_id, kind) WHERE phase_id IS NOT NULL
  DO UPDATE SET
    title       = EXCLUDED.title,
    body        = EXCLUDED.body,
    image_url   = EXCLUDED.image_url,
    update_date = EXCLUDED.update_date;
END;
$function$;

-- Views
-- NOTE: live definition has NO security_invoker, so it bypasses RLS and any
-- signed-in user can read every investor's totals -> fixed in 071.
create or replace view public.portfolio_summary as
WITH iu_agg AS (
         SELECT investor_units.investor_id,
            count(DISTINCT investor_units.project_id) AS project_count,
            sum(investor_units.issued_units) AS total_units,
            COALESCE(sum(investor_units.capital_invested), (0)::numeric) AS sum_capital_invested,
            COALESCE(sum(investor_units.token_advance_amount), (0)::numeric) AS sum_token,
            COALESCE(sum(investor_units.total_amount_received), (0)::numeric) AS sum_total_received,
            COALESCE(sum(investor_units.capital_outstanding), (0)::numeric) AS sum_outstanding,
            avg(investor_units.annual_yield_pct) AS avg_annual_yield_pct
           FROM investor_units
          WHERE (investor_units.deleted_at IS NULL)
          GROUP BY investor_units.investor_id
        ), p_agg AS (
         SELECT payouts.investor_id,
            COALESCE(sum(payouts.amount) FILTER (WHERE ((payouts.status = 'processed'::text) AND (payouts.is_demo = false))), (0)::numeric) AS sum_received,
            min(payouts.payout_date) FILTER (WHERE ((payouts.status = 'pending'::text) AND (payouts.is_demo = false))) AS next_pending_date
           FROM payouts
          GROUP BY payouts.investor_id
        )
 SELECT iu.investor_id,
    iu.project_count,
    iu.total_units,
    (iu.sum_capital_invested + iu.sum_token) AS total_invested,
    iu.sum_total_received AS total_capital_received,
    iu.sum_outstanding AS total_capital_outstanding,
    COALESCE(p.sum_received, (0)::numeric) AS total_payouts_received,
        CASE
            WHEN ((iu.sum_capital_invested + iu.sum_token) > (0)::numeric) THEN round(((COALESCE(p.sum_received, (0)::numeric) / (iu.sum_capital_invested + iu.sum_token)) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS roi_pct,
    iu.avg_annual_yield_pct,
    p.next_pending_date AS next_payout_date,
    ( SELECT payouts.amount
           FROM payouts
          WHERE ((payouts.investor_id = iu.investor_id) AND (payouts.status = 'pending'::text) AND (payouts.is_demo = false))
          ORDER BY payouts.payout_date
         LIMIT 1) AS next_payout_amount
   FROM (iu_agg iu
     LEFT JOIN p_agg p ON ((p.investor_id = iu.investor_id)));

create or replace view public.projects_public with (security_invoker=on) as
SELECT id,
    name,
    tier,
    status,
    address_line1,
    city,
    state,
    pincode,
    country,
    total_units,
    units_issued,
    units_available,
    price_per_unit,
    total_project_cost,
    total_ticket_size,
    acreage_acres,
    annual_yield_pct,
    launch_year,
    insurance_provider,
    insurance_policy_no,
    insurance_expiry_date,
    insured_amount,
    cover_image_path,
    color_hex,
    accent_hex,
    updated_at,
    is_listed_in_marketplace,
    tagline,
    subscription_deadline,
    marketplace_image,
    expected_annual_return_pct,
    marketplace_sort_order,
    llp_id,
    last_synced_at,
    approx_radius_meters
   FROM projects
  WHERE (deleted_at IS NULL);

create or replace view public.sync_status with (security_invoker=on) as
SELECT 'llps'::text AS table_name,
    (count(*))::integer AS rows,
    max(llps.last_synced_at) AS max_synced_at
   FROM llps
UNION ALL
 SELECT 'projects'::text AS table_name,
    (count(*))::integer AS rows,
    max(projects.last_synced_at) AS max_synced_at
   FROM projects
UNION ALL
 SELECT 'investors'::text AS table_name,
    (count(*))::integer AS rows,
    max(investors.last_synced_at) AS max_synced_at
   FROM investors
UNION ALL
 SELECT 'investor_units'::text AS table_name,
    (count(*))::integer AS rows,
    max(investor_units.last_synced_at) AS max_synced_at
   FROM investor_units;

-- Triggers (public schema; storage.* system triggers are managed by Supabase)
CREATE TRIGGER trg_app_config_updated_at BEFORE UPDATE ON public.app_config FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_bank_change_requests_updated_at BEFORE UPDATE ON public.bank_change_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notify_bank_change_status_change AFTER UPDATE OF status ON public.bank_change_requests FOR EACH ROW EXECUTE FUNCTION notify_bank_change_status_change();
CREATE TRIGGER trg_notify_consultation_request AFTER INSERT ON public.consultation_requests FOR EACH ROW EXECUTE FUNCTION notify_consultation_request();
CREATE TRIGGER trg_crops_updated_at BEFORE UPDATE ON public.crops FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notify_document_uploaded AFTER INSERT ON public.documents FOR EACH ROW EXECUTE FUNCTION notify_document_uploaded();
CREATE TRIGGER trg_notify_exit_request_status_change AFTER UPDATE OF status ON public.exit_requests FOR EACH ROW EXECUTE FUNCTION notify_exit_request_status_change();
CREATE TRIGGER trg_investor_units_updated_at BEFORE UPDATE ON public.investor_units FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_recompute_project_units AFTER INSERT OR DELETE OR UPDATE ON public.investor_units FOR EACH ROW EXECUTE FUNCTION trg_recompute_project_units_fn();
CREATE TRIGGER trg_investors_updated_at BEFORE UPDATE ON public.investors FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notify_investor_kyc_status_change AFTER UPDATE OF kyc_status ON public.investors FOR EACH ROW EXECUTE FUNCTION notify_investor_kyc_status_change();
CREATE TRIGGER trg_set_kyc_submitted_at BEFORE UPDATE ON public.investors FOR EACH ROW EXECUTE FUNCTION set_kyc_submitted_at();
CREATE TRIGGER trg_sync_investor_phone AFTER INSERT OR UPDATE OF phone ON public.investors FOR EACH ROW EXECUTE FUNCTION sync_investor_phone_to_auth();
CREATE TRIGGER trg_notify_kyc_resubmission_status_change AFTER UPDATE OF status ON public.kyc_resubmissions FOR EACH ROW EXECUTE FUNCTION notify_kyc_resubmission_status_change();
CREATE TRIGGER trg_payouts_updated_at BEFORE UPDATE ON public.payouts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notify_project_phase_change AFTER INSERT OR UPDATE OF status ON public.project_phases FOR EACH ROW EXECUTE FUNCTION notify_project_phase_change();
CREATE TRIGGER trg_project_phases_updated_at BEFORE UPDATE ON public.project_phases FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sync_phase_notifications AFTER UPDATE OF image_url, custom_title, custom_body, phase_date ON public.project_phases FOR EACH ROW WHEN (((old.image_url IS DISTINCT FROM new.image_url) OR (old.custom_title IS DISTINCT FROM new.custom_title) OR (old.custom_body IS DISTINCT FROM new.custom_body) OR (old.phase_date IS DISTINCT FROM new.phase_date))) EXECUTE FUNCTION sync_phase_notifications();
CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_support_tickets_updated_at BEFORE UPDATE ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notify_ticket_reply AFTER INSERT ON public.ticket_messages FOR EACH ROW EXECUTE FUNCTION notify_ticket_reply();
CREATE TRIGGER trg_user_settings_updated_at BEFORE UPDATE ON public.user_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Row level security
alter table public.app_config enable row level security;
alter table public.app_releases enable row level security;
alter table public.auth_request_throttle enable row level security;
alter table public.bank_change_requests enable row level security;
alter table public.consents enable row level security;
alter table public.consultation_requests enable row level security;
alter table public.crops enable row level security;
alter table public.documents enable row level security;
alter table public.erasure_requests enable row level security;
alter table public.exit_requests enable row level security;
alter table public.gallery_photos enable row level security;
alter table public.investor_units enable row level security;
alter table public.investors enable row level security;
alter table public.kyc_resubmissions enable row level security;
alter table public.llps enable row level security;
alter table public.login_events enable row level security;
alter table public.nominees enable row level security;
alter table public.notifications enable row level security;
alter table public.payouts enable row level security;
alter table public.phase_copy enable row level security;
alter table public.project_documents enable row level security;
alter table public.project_phases enable row level security;
alter table public.project_updates enable row level security;
alter table public.projects enable row level security;
alter table public.support_tickets enable row level security;
alter table public.sync_alerts enable row level security;
alter table public.ticket_messages enable row level security;
alter table public.user_settings enable row level security;
alter table public.webhook_log enable row level security;

-- Policies
create policy "app_config: public read" on public.app_config as permissive for select to anon, authenticated
  using (true);
create policy "public read app_releases" on public.app_releases as permissive for select to authenticated
  using (true);
create policy "auth_request_throttle: deny all" on public.auth_request_throttle as permissive for all to anon, authenticated
  using (false);
create policy "admin read all" on public.bank_change_requests as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.bank_change_requests as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "bank_change_requests: read own rows" on public.bank_change_requests as permissive for select to authenticated
  using ((investor_id = ( SELECT uid() AS uid)));
create policy "consents: insert own" on public.consents as permissive for insert to authenticated
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "consents: read own" on public.consents as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.consultation_requests as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.consultation_requests as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "consultation_requests: insert own" on public.consultation_requests as permissive for insert to authenticated
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "consultation_requests: select own" on public.consultation_requests as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "admin delete" on public.crops as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.crops as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.crops as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.crops as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "crops: via investor units" on public.crops as permissive for select to authenticated
  using ((project_id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT uid() AS uid)))));
create policy "admin delete" on public.documents as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.documents as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.documents as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.documents as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "documents: insert own investor doc" on public.documents as permissive for insert to authenticated
  with check (((visibility = 'investor'::text) AND (investor_id = ( SELECT uid() AS uid))));
create policy "documents: tiered read" on public.documents as permissive for select to authenticated
  using (((visibility = 'common'::text) OR ((visibility = 'project'::text) AND (project_id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT uid() AS uid))))) OR ((visibility = 'investor'::text) AND (investor_id = ( SELECT uid() AS uid)))));
create policy "erasure: insert own" on public.erasure_requests as permissive for insert to authenticated
  with check ((investor_id = ( SELECT uid() AS uid)));
create policy "erasure: read own" on public.erasure_requests as permissive for select to authenticated
  using ((investor_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.exit_requests as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.exit_requests as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "exit_requests: insert own" on public.exit_requests as permissive for insert to authenticated
  with check (((user_id = ( SELECT uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM investor_units iu
  WHERE ((iu.id = exit_requests.investor_unit_id) AND (iu.investor_id = ( SELECT uid() AS uid)) AND (iu.investment_date IS NOT NULL) AND ((iu.investment_date + '5 years'::interval) <= now()))))));
create policy "exit_requests: select own" on public.exit_requests as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "admin delete" on public.gallery_photos as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.gallery_photos as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.gallery_photos as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.gallery_photos as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "gallery_photos: via investor units" on public.gallery_photos as permissive for select to authenticated
  using ((project_id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT uid() AS uid)))));
create policy "admin read all" on public.investor_units as permissive for select to authenticated
  using (is_admin());
create policy "investor_units: read own rows" on public.investor_units as permissive for select to authenticated
  using (((investor_id = ( SELECT uid() AS uid)) AND (deleted_at IS NULL)));
create policy "admin read all" on public.investors as permissive for select to authenticated
  using (is_admin());
create policy "investors: insert own row" on public.investors as permissive for insert to authenticated
  with check ((id = ( SELECT uid() AS uid)));
create policy "investors: read own row" on public.investors as permissive for select to authenticated
  using (((id = ( SELECT uid() AS uid)) AND (deleted_at IS NULL)));
create policy "investors: update own row" on public.investors as permissive for update to authenticated
  using ((id = ( SELECT uid() AS uid)))
  with check ((id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.kyc_resubmissions as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.kyc_resubmissions as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "kyc_resubmissions: insert own" on public.kyc_resubmissions as permissive for insert to authenticated
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "kyc_resubmissions: select own" on public.kyc_resubmissions as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.llps as permissive for select to authenticated
  using (is_admin());
create policy "llps: visible via owned projects" on public.llps as permissive for select to authenticated
  using (((deleted_at IS NULL) AND (id IN ( SELECT p.llp_id
   FROM (projects p
     JOIN investor_units iu ON ((iu.project_id = p.id)))
  WHERE ((iu.investor_id = ( SELECT uid() AS uid)) AND (p.deleted_at IS NULL))))));
create policy "login_events: insert own row" on public.login_events as permissive for insert to authenticated
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "login_events: read own rows" on public.login_events as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.nominees as permissive for select to authenticated
  using (is_admin());
create policy "nominees: manage own" on public.nominees as permissive for all to authenticated
  using ((investor_id = ( SELECT uid() AS uid)))
  with check ((investor_id = ( SELECT uid() AS uid)));
create policy "admin delete" on public.notifications as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.notifications as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.notifications as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.notifications as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "notifications: mark own as read" on public.notifications as permissive for update to authenticated
  using ((investor_id = ( SELECT uid() AS uid)))
  with check ((investor_id = ( SELECT uid() AS uid)));
create policy "notifications: read own rows" on public.notifications as permissive for select to authenticated
  using ((investor_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.payouts as permissive for select to authenticated
  using (is_admin());
create policy "payouts: read own rows" on public.payouts as permissive for select to authenticated
  using ((investor_id = ( SELECT uid() AS uid)));
create policy "phase_copy: readable by signed-in users" on public.phase_copy as permissive for select to authenticated
  using (true);
create policy "admin delete" on public.project_documents as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.project_documents as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.project_documents as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.project_documents as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "project_documents: investor read" on public.project_documents as permissive for select to authenticated
  using (((is_public = true) OR (EXISTS ( SELECT 1
   FROM investor_units u
  WHERE ((u.project_id = project_documents.project_id) AND (u.investor_id = ( SELECT uid() AS uid)) AND (u.deleted_at IS NULL) AND (COALESCE(u.issued_units, 0) > 0))))));
create policy "admin delete" on public.project_phases as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.project_phases as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.project_phases as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.project_phases as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "project_phases: via investor units" on public.project_phases as permissive for select to authenticated
  using ((project_id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT uid() AS uid)))));
create policy "admin delete" on public.project_updates as permissive for delete to authenticated
  using (is_admin());
create policy "admin insert" on public.project_updates as permissive for insert to authenticated
  with check (is_admin());
create policy "admin read all" on public.project_updates as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.project_updates as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "project_updates: via investor units" on public.project_updates as permissive for select to authenticated
  using ((project_id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE ((investor_units.investor_id = ( SELECT uid() AS uid)) AND (investor_units.deleted_at IS NULL)))));
create policy "admin read all" on public.projects as permissive for select to authenticated
  using (is_admin());
create policy "admin update" on public.projects as permissive for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy "projects: visible to investors with units OR marketplace" on public.projects as permissive for select to authenticated
  using (((deleted_at IS NULL) AND ((is_listed_in_marketplace = true) OR (id IN ( SELECT investor_units.project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT uid() AS uid)))))));
create policy "admin read all" on public.support_tickets as permissive for select to authenticated
  using (is_admin());
create policy "support_tickets: read own rows" on public.support_tickets as permissive for select to authenticated
  using ((investor_id = ( SELECT uid() AS uid)));
create policy "admin read all" on public.ticket_messages as permissive for select to authenticated
  using (is_admin());
create policy "ticket_messages: read via own tickets" on public.ticket_messages as permissive for select to authenticated
  using ((ticket_id IN ( SELECT support_tickets.id
   FROM support_tickets
  WHERE (support_tickets.investor_id = ( SELECT uid() AS uid)))));
create policy "user_settings: insert own row" on public.user_settings as permissive for insert to authenticated
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "user_settings: read own row" on public.user_settings as permissive for select to authenticated
  using ((user_id = ( SELECT uid() AS uid)));
create policy "user_settings: update own row" on public.user_settings as permissive for update to authenticated
  using ((user_id = ( SELECT uid() AS uid)))
  with check ((user_id = ( SELECT uid() AS uid)));
create policy "webhook_log: deny all authenticated users" on public.webhook_log as permissive for all to authenticated
  using (false);

-- Storage policies (storage.objects)
create policy "admin read arl buckets" on storage.objects as permissive for select to authenticated
  using (((bucket_id = ANY (ARRAY['arl-documents'::text, 'arl-gallery'::text])) AND is_admin()));
create policy "admin upload arl buckets" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = ANY (ARRAY['arl-documents'::text, 'arl-gallery'::text])) AND is_admin()));
create policy "investors read common documents" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'arl-documents'::text) AND ((storage.foldername(name))[1] = 'common'::text)));
create policy "investors read gallery for their projects" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'arl-gallery'::text) AND ((storage.foldername(name))[2] IN ( SELECT (investor_units.project_id)::text AS project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT auth.uid() AS uid))))));
create policy "investors read own investor documents" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'arl-documents'::text) AND ((storage.foldername(name))[1] = 'investor'::text) AND ((storage.foldername(name))[2] = ( SELECT (auth.uid())::text AS uid))));
create policy "investors read project documents" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'arl-documents'::text) AND ((storage.foldername(name))[1] = 'project'::text) AND ((storage.foldername(name))[2] IN ( SELECT (investor_units.project_id)::text AS project_id
   FROM investor_units
  WHERE (investor_units.investor_id = ( SELECT auth.uid() AS uid))))));
create policy "service role full access arl-documents" on storage.objects as permissive for all to service_role
  using ((bucket_id = 'arl-documents'::text))
  with check ((bucket_id = 'arl-documents'::text));
create policy "service role full access arl-gallery" on storage.objects as permissive for all to service_role
  using ((bucket_id = 'arl-gallery'::text))
  with check ((bucket_id = 'arl-gallery'::text));

-- Table privileges (reproduced from pg_class.relacl; RLS is what actually
-- gates access - several tables still carry Supabase's default full grants)
revoke all on public.app_config from anon, authenticated;
grant select on public.app_config to authenticated;
grant select on public.app_config to anon;
revoke all on public.app_releases from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.app_releases to anon, authenticated;
revoke all on public.auth_request_throttle from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.auth_request_throttle to anon, authenticated;
revoke all on public.bank_change_requests from anon, authenticated;
grant select on public.bank_change_requests to authenticated;
revoke all on public.consents from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.consents to anon, authenticated;
revoke all on public.consultation_requests from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.consultation_requests to authenticated;
revoke all on public.crops from anon, authenticated;
grant select on public.crops to authenticated;
revoke all on public.documents from anon, authenticated;
grant select on public.documents to authenticated;
revoke all on public.erasure_requests from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.erasure_requests to anon, authenticated;
revoke all on public.exit_requests from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.exit_requests to authenticated;
revoke all on public.gallery_photos from anon, authenticated;
grant select on public.gallery_photos to authenticated;
revoke all on public.investor_units from anon, authenticated;
grant select on public.investor_units to authenticated;
revoke all on public.investors from anon, authenticated;
grant insert, select, update on public.investors to authenticated;
revoke all on public.kyc_resubmissions from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.kyc_resubmissions to authenticated;
revoke all on public.llps from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.llps to authenticated;
revoke all on public.login_events from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.login_events to authenticated;
revoke all on public.nominees from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.nominees to anon, authenticated;
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
revoke all on public.payouts from anon, authenticated;
grant select on public.payouts to authenticated;
revoke all on public.phase_copy from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.phase_copy to anon, authenticated;
revoke all on public.portfolio_summary from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.portfolio_summary to authenticated;
revoke all on public.project_documents from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.project_documents to anon, authenticated;
revoke all on public.project_phases from anon, authenticated;
grant select on public.project_phases to authenticated;
revoke all on public.project_updates from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.project_updates to anon, authenticated;
revoke all on public.projects from anon, authenticated;
grant select on public.projects to authenticated;
revoke all on public.projects_public from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.projects_public to anon, authenticated;
revoke all on public.support_tickets from anon, authenticated;
grant select on public.support_tickets to authenticated;
revoke all on public.sync_alerts from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.sync_alerts to authenticated;
revoke all on public.sync_status from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.sync_status to authenticated;
revoke all on public.ticket_messages from anon, authenticated;
grant select on public.ticket_messages to authenticated;
revoke all on public.user_settings from anon, authenticated;
grant insert, select, update, delete, truncate, references, trigger on public.user_settings to authenticated;
revoke all on public.webhook_log from anon, authenticated;
grant select on public.webhook_log to authenticated;

-- Function execute privileges
revoke execute on function public.broadcast_new_project_notification(p_project_id uuid, p_project_name text) from public, anon, authenticated;
revoke execute on function public.broadcast_phase_update_notification(p_project_id uuid, p_phase_name text, p_project_name text) from public, anon, authenticated;
revoke execute on function public.check_auth_throttle(p_key text, p_limit integer, p_window_secs integer) from public, anon, authenticated;
revoke execute on function public.get_portfolio_summary() from public, anon, authenticated;
grant execute on function public.get_portfolio_summary() to public, anon, authenticated;
revoke execute on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
revoke execute on function public.notify_bank_change_status_change() from public, anon, authenticated;
revoke execute on function public.notify_consultation_request() from public, anon, authenticated;
revoke execute on function public.notify_document_uploaded() from public, anon, authenticated;
revoke execute on function public.notify_exit_request_status_change() from public, anon, authenticated;
revoke execute on function public.notify_investor_kyc_status_change() from public, anon, authenticated;
revoke execute on function public.notify_kyc_resubmission_status_change() from public, anon, authenticated;
revoke execute on function public.notify_project_phase_change() from public, anon, authenticated;
revoke execute on function public.notify_ticket_reply() from public, anon, authenticated;
revoke execute on function public.purge_expired_personal_data() from public, anon, authenticated;
revoke execute on function public.recompute_project_units(p_project_id uuid) from public, anon, authenticated;
revoke execute on function public.resolve_phase_copy(p_phase project_phases, p_kind text, p_project_name text) from public, anon, authenticated;
grant execute on function public.resolve_phase_copy(p_phase project_phases, p_kind text, p_project_name text) to public, anon, authenticated;
revoke execute on function public.set_kyc_submitted_at() from public, anon, authenticated;
grant execute on function public.set_kyc_submitted_at() to public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
grant execute on function public.set_updated_at() to public, anon, authenticated;
revoke execute on function public.sync_investor_phone_to_auth() from public, anon, authenticated;
revoke execute on function public.sync_phase_notifications() from public, anon, authenticated;
grant execute on function public.sync_phase_notifications() to public, anon, authenticated;
revoke execute on function public.trg_recompute_project_units_fn() from public, anon, authenticated;
revoke execute on function public.uid() from public, anon, authenticated;
grant execute on function public.uid() to public, anon, authenticated;
revoke execute on function public.upsert_phase_project_update(p_phase project_phases, p_kind text, p_title text, p_body text) from public, anon, authenticated;
grant execute on function public.upsert_phase_project_update(p_phase project_phases, p_kind text, p_title text, p_body text) to public, anon, authenticated;

-- Realtime publication: the live project publishes NO public tables
-- (supabase_realtime is empty). ticket_detail_screen subscribes to
-- ticket_messages / support_tickets, so live ticket updates never arrive.
-- Left as-is here; see 071 for the opt-in fix.

-- Storage buckets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('APK', 'APK', true, null, array['application/vnd.android.package-archive']) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('arl-documents', 'arl-documents', false, 52428800, array['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 'text/plain', 'text/csv', 'image/jpeg', 'image/png', 'image/webp']) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('arl-gallery', 'arl-gallery', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('arl-public', 'arl-public', true, 10485760, array['image/jpeg', 'image/png', 'image/webp']) on conflict (id) do nothing;

-- Cron jobs (pg_cron)
select cron.schedule('purge-old-webhook-logs', '0 2 * * 0', 'DELETE FROM public.webhook_log
    WHERE received_at < NOW() - INTERVAL ''90 days'';');
select cron.schedule('purge-expired-personal-data', '0 3 * * 0', 'select public.purge_expired_personal_data();');
-- The jobs below POST to Edge Functions with a secret header. Recreate them
-- by hand with the secret from Vault - never commit the header value:
--   gallery-sync-daily        30 0 * * *   -> functions/v1/gallery-sync
--   zoho-reconcile-daily      0 1 * * *    -> functions/v1/zoho-reconcile-daily
--   documents-sync-daily      45 0 * * *   -> functions/v1/documents-sync
--   health-check-daily        0 7 * * *    -> functions/v1/health-check
--   sync-stale-alert-hourly   0 * * * *    -> functions/v1/sync-stale-alert
--     (NOTE: has written ~8,000 sync_alerts rows since May; thresholds are
--      tighter than the real Zoho sync cadence.)
--
-- Edge Functions deployed on 2026-09-26 (slug, version): onboard-investor 14,
-- zoho-crm-webhook 35, create-ticket 14, reply-ticket 14, bank-change-request 14,
-- gallery-sync 15, crm-resync 7, zoho-reconcile-daily 14, sync-stale-alert 8,
-- notify-consultation-request 5, request-auth-email 10, latest-app-version 3,
-- notify-bank-update 1, documents-sync 10, zoho-write 4, zoho-docs 2.
-- Repo is behind for request-auth-email (v10 adds rate limiting) and is
-- missing crm-resync, notify-bank-update, zoho-write, zoho-docs.
