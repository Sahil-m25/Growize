-- ============================================================
-- Regression test for migration 066 (phase_update notifications)
--
-- Fixture mirrors PRODUCTION as verified 2026-08-22 against project
-- ref oynfhdqizebvgmaoiuax ("Growize Main DB", Postgres 17.6) — NOT
-- what the repo's archived migrations imply. The differences matter:
--
--   * `projects` has NO zoho_llp_id. The Zoho id lives on
--     `llps.zoho_llp_id`; `projects.llp_id` -> `llps.id`.
--   * `project_phases` has NO started_at / completed_at (archived
--     migration 053 never reached prod). T7 pins this down — if the
--     trigger ever starts referencing those columns, this test fails.
--   * `investor_units` and `projects` are soft-deleted via deleted_at.
--   * notifications_type_check in prod ALREADY lists phase_update /
--     document / new_project, so 066 is a no-op on it. P1 pins that.
--
-- Verified green on PostgreSQL 16.13 — 18 assertions.
--
-- Usage:
--   createdb ekatest
--   psql -d ekatest -c "CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;"
--   psql -d ekatest -v ON_ERROR_STOP=1 -f supabase/tests/066_phase_update_notifications_test.sql
--   psql -d ekatest -v ON_ERROR_STOP=1 -f supabase/migrations/20260822000000_066_phase_update_notifications.sql
--   psql -d ekatest -v ON_ERROR_STOP=1 -f supabase/tests/066_assertions.sql
-- ============================================================

-- Mirrors PRODUCTION schema as verified 2026-08-22 (ref oynfhdqizebvgmaoiuax).
CREATE TABLE public.investors (
  id UUID PRIMARY KEY, arl_id TEXT UNIQUE NOT NULL, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL
);
CREATE TABLE public.llps (
  id UUID PRIMARY KEY, zoho_llp_id TEXT UNIQUE, name TEXT NOT NULL, llp_status TEXT
);
CREATE TABLE public.projects (
  id UUID PRIMARY KEY, name TEXT NOT NULL, status TEXT, total_units INT, units_issued INT,
  launch_year DATE, llp_id UUID REFERENCES public.llps(id), updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ                      -- soft delete, prod has this
);
CREATE TABLE public.investor_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id UUID NOT NULL REFERENCES public.investors(id),
  project_id  UUID NOT NULL REFERENCES public.projects(id),
  issued_units INT, reserved_units INT, allocation_status TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ                      -- soft delete, prod has this
);
CREATE TABLE public.user_settings (
  user_id UUID PRIMARY KEY REFERENCES public.investors(id),
  biometric_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id UUID NOT NULL REFERENCES public.investors(id),
  type TEXT NOT NULL, title TEXT NOT NULL, body TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  read_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT NOW()
);
-- The constraint AS PROD HAS IT TODAY (already widened, unlike the repo).
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY['payout','photo','ticket','reminder','milestone','kyc','exit',
                    'bank_change','new_project','phase_update','document'])
);
-- project_phases WITHOUT started_at / completed_at — migration 053 never
-- reached prod. If the trigger referenced those columns it would fail here.
CREATE TABLE public.project_phases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_phase_id TEXT UNIQUE, phase_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('done','current','pending')),
  phase_date DATE, sort_order INT NOT NULL DEFAULT 0,
  sub_items JSONB NOT NULL DEFAULT '[]', updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.llps (id, zoho_llp_id, name, llp_status) VALUES
  ('6cb9fe7c-b173-4e39-a613-93bda03ca9f4','1169101000001929260','EKA LLP','Open for Reservation'),
  ('cccccccc-0000-0000-0000-00000000000c','9999999999999999999','OTHER LLP','Operational'),
  ('dddddddd-0000-0000-0000-00000000000d','8888888888888888888','GONE LLP','Closed');
INSERT INTO public.projects (id, name, status, total_units, units_issued, launch_year, llp_id, deleted_at) VALUES
  ('6cb9fe7c-b173-4e39-a613-93bda03ca9f4','EKA LLP','Open for Reservation',22,2,'2026-06-12','6cb9fe7c-b173-4e39-a613-93bda03ca9f4',NULL),
  ('22222222-2222-2222-2222-222222222222','OTHER LLP','operational',10,5,'2026-01-01','cccccccc-0000-0000-0000-00000000000c',NULL),
  ('33333333-3333-3333-3333-333333333333','GONE LLP','operational',10,5,'2026-01-01','dddddddd-0000-0000-0000-00000000000d',NOW());
INSERT INTO public.investors (id, arl_id, name, email) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001','ARL-00001','Eka One','one@x.com'),
  ('aaaaaaaa-0000-0000-0000-000000000002','ARL-00002','Eka Two','two@x.com'),
  ('aaaaaaaa-0000-0000-0000-000000000003','ARL-00003','Eka OptedOut','three@x.com'),
  ('aaaaaaaa-0000-0000-0000-000000000004','ARL-00004','Eka Withdrawn','four@x.com'),
  ('aaaaaaaa-0000-0000-0000-000000000005','ARL-00005','Other Project','five@x.com'),
  ('aaaaaaaa-0000-0000-0000-000000000006','ARL-00006','Deleted Project','six@x.com');
INSERT INTO public.investor_units (investor_id, project_id, issued_units, allocation_status, deleted_at) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001','6cb9fe7c-b173-4e39-a613-93bda03ca9f4',1,'Issued',NULL),
  ('aaaaaaaa-0000-0000-0000-000000000002','6cb9fe7c-b173-4e39-a613-93bda03ca9f4',1,'Issued',NULL),
  ('aaaaaaaa-0000-0000-0000-000000000003','6cb9fe7c-b173-4e39-a613-93bda03ca9f4',1,'Issued',NULL),
  ('aaaaaaaa-0000-0000-0000-000000000004','6cb9fe7c-b173-4e39-a613-93bda03ca9f4',1,'Issued',NOW()),
  ('aaaaaaaa-0000-0000-0000-000000000005','22222222-2222-2222-2222-222222222222',1,'Issued',NULL),
  ('aaaaaaaa-0000-0000-0000-000000000006','33333333-3333-3333-3333-333333333333',1,'Issued',NULL);
INSERT INTO public.user_settings (user_id, notifications_enabled) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000003', FALSE);
