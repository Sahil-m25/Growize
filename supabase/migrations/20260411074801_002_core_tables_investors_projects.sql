
-- ============================================================
-- MIGRATION 002 — INVESTORS & PROJECTS
-- Source of truth: Zoho CRM
--   Investors   ← Contacts module
--   Projects    ← LLP_Creation_Module
-- Auth: Supabase email invite (Option B) — no Zoho OAuth
-- Sensitive fields (PAN, Aadhaar, bank account) stored MASKED only
-- ============================================================

-- -------------------------------------------------------
-- INVESTORS
-- Mirrors: Zoho CRM > Contacts
-- Created by: onboard-investor Edge Function (inviteUserByEmail)
-- Updated by: zoho-crm-webhook on Contact change
-- -------------------------------------------------------
CREATE TABLE public.investors (
  -- Auth
  id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  zoho_contact_id       TEXT UNIQUE,                    -- Contacts.id — used for webhook mapping

  -- Identity
  arl_id                TEXT UNIQUE NOT NULL,            -- e.g. "ARL-00142" — assigned by ARL staff
  name                  TEXT NOT NULL,
  email                 TEXT UNIQUE NOT NULL,
  phone                 TEXT,
  salutation            TEXT,                            -- Mr. / Ms. / Dr.

  -- KYC — Contacts.KYC
  kyc_status            TEXT NOT NULL DEFAULT 'pending'
                          CHECK (kyc_status IN ('pending','in_progress','verified','rejected')),

  -- Sensitive fields — MASKED only, never raw
  -- PAN_Number → masked e.g. "RTYUI****L"
  pan_masked            TEXT,
  -- Bank_Account_Number → masked e.g. "XXXX-XXXX-9012"
  bank_account_masked   TEXT,
  bank_ifsc             TEXT,                            -- ISFC_Code
  bank_branch           TEXT,                            -- Bank_Branch
  bank_holder_name      TEXT,                            -- Account_Holder_Full_name
  bank_name             TEXT,

  -- Address — Mailing fields from Contacts
  address_line1         TEXT,
  address_line2         TEXT,
  city                  TEXT,
  state                 TEXT,
  pincode               TEXT,
  country               TEXT,

  -- Status flags from Contacts (useful for onboarding tracking)
  unit_allocated        BOOLEAN DEFAULT FALSE,           -- Contacts.Unit_allocated
  payment_received      BOOLEAN DEFAULT FALSE,           -- Contacts.Payment_received
  profile_verified      BOOLEAN DEFAULT FALSE,           -- Contacts.Profile_verified
  agreement_signed      BOOLEAN DEFAULT FALSE,           -- Contacts.Agreement_signed
  fema_applicable       BOOLEAN DEFAULT FALSE,           -- Contacts.FEMA_Applicable

  -- Timestamps
  onboarded_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.investors IS
  'One row per investor. Mirrors Zoho CRM Contacts. PAN and bank account stored masked only. Auth via Supabase invite.';

-- -------------------------------------------------------
-- PROJECTS  (called "LLPs" in Zoho)
-- Mirrors: Zoho CRM > LLP_Creation_Module
-- Shared table — not investor-specific
-- Linked to investors via investor_units
-- -------------------------------------------------------
CREATE TABLE public.projects (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zoho_llp_id           TEXT UNIQUE,                    -- LLP_Creation_Module.id

  -- Identity
  name                  TEXT NOT NULL,                  -- LLP_Creation_Module.Name
  tier                  TEXT,                           -- e.g. "10 L"
  llp_status            TEXT,                           -- "Open for Issuance", "Closed" etc.
  llp_owner             TEXT,                           -- LLP_Owner (person name)
  incorporation_no      TEXT,                           -- Incorporation_No
  gst                   TEXT,                           -- GST
  pan                   TEXT,                           -- LLP PAN (entity PAN, not investor — ok to store)

  -- Location
  address_line1         TEXT,
  city                  TEXT,
  state                 TEXT,
  pincode               TEXT,
  country               TEXT,

  -- Financials
  total_units           INT,                            -- Total_Units
  units_issued          INT,                            -- Units_Issued
  units_available       INT,                            -- Units_Available_to_Issue
  price_per_unit        NUMERIC(14,2),                  -- Pet_Unit_Price
  total_project_cost    NUMERIC(14,2),                  -- Total_Project_Cost
  total_ticket_size     NUMERIC(14,2),                  -- Total_Ticket_Size

  -- Farm details
  acreage_acres         NUMERIC(10,2),                  -- Acreage_Acres
  annual_yield_pct      NUMERIC(5,2),                   -- Annual_Rental_Yield (numeric form of "19%")
  launch_year           DATE,                           -- Launch_Year

  -- Insurance
  insurance_provider    TEXT,
  insurance_policy_no   TEXT,
  insurance_expiry_date DATE,
  insured_amount        NUMERIC(14,2),

  -- SPOC (point of contact for investor queries about this project)
  spoc1_name            TEXT,                           -- SPOC_1_Full_Name
  spoc1_phone           TEXT,                           -- SPOC_1_Contact_No
  spoc2_name            TEXT,
  spoc2_phone           TEXT,

  -- App display
  cover_image_path      TEXT,                           -- Supabase Storage path for hero image
  color_hex             TEXT NOT NULL DEFAULT '#1A2F24',
  accent_hex            TEXT NOT NULL DEFAULT '#2E7D6E',

  -- Timestamps
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.projects IS
  'ARL farm projects (LLPs). Mirrors LLP_Creation_Module. Shared across all investors who have units.';
