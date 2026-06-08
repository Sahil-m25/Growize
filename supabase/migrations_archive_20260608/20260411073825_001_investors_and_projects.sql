
-- ============================================================
-- MIGRATION 001 — INVESTORS & PROJECTS CORE TABLES
-- ARL Investor App — AgResearch Labs
-- Auth: Direct Supabase Auth (email invite flow)
-- Zoho CRM is source of truth; Supabase is read-optimised mirror
-- ============================================================

-- ============================================================
-- INVESTORS TABLE
-- One row per investor = one Supabase auth.users row
-- Created via onboard-investor Edge Function (inviteUserByEmail)
-- Updated via zoho-crm-webhook when CRM Contact record changes
-- ============================================================
CREATE TABLE public.investors (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  arl_id          TEXT UNIQUE NOT NULL,           -- ARL's internal ID e.g. "ARL-00142"
  zoho_contact_id TEXT UNIQUE,                    -- Zoho CRM Contact ID for webhook mapping
  name            TEXT NOT NULL,
  email           TEXT UNIQUE NOT NULL,
  phone           TEXT,
  kyc_status      TEXT NOT NULL DEFAULT 'pending'
                    CHECK (kyc_status IN ('pending','verified','rejected')),
  pan_masked      TEXT,                           -- "ABCPX****X"  — never store raw PAN
  aadhaar_masked  TEXT,                           -- "XXXX-XXXX-1234" — never store raw Aadhaar
  address_json    JSONB DEFAULT '{}',             -- { "line1":"", "line2":"", "city":"", "state":"", "pincode":"" }
  bank_name       TEXT,
  bank_account_masked TEXT,                       -- "XXXX-XXXX-1234"
  bank_ifsc       TEXT,
  bank_holder     TEXT,
  onboarded_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.investors IS 'One row per investor. Mirrors Zoho CRM Contact. Auth managed by Supabase.';

-- ============================================================
-- PROJECTS TABLE
-- Shared table — all projects that ARL runs
-- Not investor-specific; investor_units table links investors to projects
-- Updated via zoho-crm-webhook
-- ============================================================
CREATE TABLE public.projects (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zoho_project_id TEXT UNIQUE,                    -- Zoho CRM custom module record ID
  name            TEXT NOT NULL,
  location        TEXT,
  description     TEXT,
  status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','operational','completed')),
  cover_image_path TEXT,                          -- Supabase Storage path for project hero image
  color_hex       TEXT NOT NULL DEFAULT '#1A2F24', -- ARL green default; overrideable per project
  accent_hex      TEXT NOT NULL DEFAULT '#2E7D6E',
  start_date      DATE,
  end_date        DATE,
  total_months    INT,
  price_per_unit  NUMERIC(14,2),                  -- for Explore screen calculator
  annual_yield_pct NUMERIC(5,2),                  -- expected annual yield % for calculator
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.projects IS 'ARL farm projects. Shared — visible to all investors who have units in them.';

-- ============================================================
-- INVESTOR UNITS TABLE
-- Junction table: which investor owns how many units in which project
-- Source of truth for financial commitment amounts
-- ============================================================
CREATE TABLE public.investor_units (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id       UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,
  project_id        UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_unit_id      TEXT UNIQUE,                  -- Zoho CRM custom module record ID
  unit_count        INT NOT NULL DEFAULT 1,
  committed_amount  NUMERIC(14,2) NOT NULL DEFAULT 0,  -- total amount investor agreed to pay
  received_amount   NUMERIC(14,2) NOT NULL DEFAULT 0,  -- capital actually received by ARL
  pending_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,  -- capital still outstanding
  allocated_at      DATE,
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(investor_id, project_id)
);

COMMENT ON TABLE public.investor_units IS 'Links investors to projects. Tracks capital commitment and receipt.';

-- ============================================================
-- PROJECT PHASES TABLE
-- Timeline milestones for each project (e.g. Land Prep, Planting, First Harvest)
-- Shown as a timeline widget in the app
-- ============================================================
CREATE TABLE public.project_phases (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_phase_id TEXT UNIQUE,
  phase_name    TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('done','current','pending')),
  phase_date    DATE,
  sub_items     JSONB NOT NULL DEFAULT '[]',
  -- sub_items format:
  -- [{ "label": "2.1", "detail": "pH analysis complete", "date": "2026-02-20", "done": true }]
  sort_order    INT NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.project_phases IS 'Project timeline milestones. sub_items holds nested checklist items as JSONB.';

-- ============================================================
-- CROPS TABLE
-- Crops grown in each project cycle
-- is_current=TRUE marks the active crop; others are history
-- ============================================================
CREATE TABLE public.crops (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_crop_id  TEXT UNIQUE,
  name          TEXT NOT NULL,
  emoji         TEXT DEFAULT '🌱',
  start_date    DATE,
  end_date      DATE,
  harvest_date  DATE,
  progress_pct  INT NOT NULL DEFAULT 0 CHECK (progress_pct BETWEEN 0 AND 100),
  is_current    BOOLEAN NOT NULL DEFAULT FALSE,
  revenue       NUMERIC(14,2),                   -- filled post-harvest from payout data
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.crops IS 'Crop cycles per project. is_current=true marks active crop; historical rows kept.';
