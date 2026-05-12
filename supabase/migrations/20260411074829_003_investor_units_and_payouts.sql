
-- ============================================================
-- MIGRATION 003 — INVESTOR UNITS & PAYOUTS
-- Source of truth: Zoho CRM > LLP_UnitAllocation_Module
-- One investor can have units in multiple projects (confirmed).
-- One investor can have MULTIPLE unit allocation records per project
--   (no UNIQUE constraint on investor_id + project_id).
-- Payouts are unpacked from the 10 UTR/Amount/Date field-sets
--   on the LLP_UnitAllocation_Module into individual rows here.
-- When Zoho Books is connected later, payouts can be
--   supplemented/replaced by zoho-books-webhook — same table,
--   just add zoho_invoice_id and set source='books'.
-- ============================================================

-- -------------------------------------------------------
-- INVESTOR UNITS
-- Mirrors: LLP_UnitAllocation_Module
-- One row per allocation record (investor ↔ project)
-- -------------------------------------------------------
CREATE TABLE public.investor_units (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zoho_allocation_id      TEXT UNIQUE,                  -- LLP_UnitAllocation_Module.id

  investor_id             UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,
  project_id              UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- Unit counts — LLP_UnitAllocation_Module fields
  issued_units            INT NOT NULL DEFAULT 0,       -- Issued_Units
  reserved_units          INT NOT NULL DEFAULT 0,       -- Reserved_Units

  -- Capital — LLP_UnitAllocation_Module fields
  unit_price              NUMERIC(14,2),                -- Unit_Price
  capital_invested        NUMERIC(14,2) DEFAULT 0,      -- Capital_Invested
  capital_outstanding     NUMERIC(14,2) DEFAULT 0,      -- Capital_Outstanding
  capital_returns         NUMERIC(14,2) DEFAULT 0,      -- Capital_Returns
  total_amount_receivable NUMERIC(14,2) DEFAULT 0,      -- Total_Amount_Receivable
  total_amount_received   NUMERIC(14,2) DEFAULT 0,      -- Total_Amount_Received
  token_advance_amount    NUMERIC(14,2) DEFAULT 0,      -- Token_Advance_Amount

  -- Yield
  annual_yield_pct        NUMERIC(5,2),                 -- Annual_Rental_Yield parsed to numeric

  -- Status
  allocation_status       TEXT,                         -- Allocation_Status
  customer_status         TEXT,                         -- Customer_Status ("Active" etc.)

  -- Dates
  investment_date         DATE,                         -- Investment_Date
  next_payout_date        DATE,                         -- Next_Payout

  -- Timestamps
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.investor_units IS
  'Mirrors LLP_UnitAllocation_Module. One row per CRM allocation record. No unique constraint on '
  '(investor_id, project_id) — one investor may have multiple allocation records per project.';

-- -------------------------------------------------------
-- PAYOUTS
-- Unpacked from LLP_UnitAllocation_Module UTR/Amount/Date 1-10
-- Each field-set becomes one row here.
-- Modular: zoho-books-webhook can add rows with source='books'
--   and zoho_invoice_id set — no schema change needed.
-- -------------------------------------------------------
CREATE TABLE public.payouts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Links
  investor_id         UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  allocation_id       UUID REFERENCES public.investor_units(id) ON DELETE SET NULL,

  -- Source tracking — makes Books plug-in seamless later
  -- 'crm'   = unpacked from LLP_UnitAllocation_Module UTR fields
  -- 'books' = pushed by zoho-books-webhook (future)
  -- 'manual'= inserted directly in Supabase Studio
  source              TEXT NOT NULL DEFAULT 'crm'
                        CHECK (source IN ('crm','books','manual')),
  zoho_invoice_id     TEXT UNIQUE,                     -- populated by books webhook; NULL for crm source

  -- Payout data
  amount              NUMERIC(14,2) NOT NULL,
  payout_date         DATE,
  utr                 TEXT,                            -- bank transfer reference
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','processed','on_hold')),

  -- Optional detail
  crop_name           TEXT,
  notes               TEXT,

  -- Idempotency — prevents duplicate rows on webhook re-delivery
  -- For CRM source: hash of (zoho_allocation_id + utr + amount)
  -- For Books source: zoho_invoice_id serves this role
  idempotency_key     TEXT UNIQUE,

  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.payouts IS
  'Individual payout records. Sourced from LLP_UnitAllocation_Module (UTR/Amount/Date fields unpacked). '
  'source=books rows added later by zoho-books-webhook — no schema change required.';

-- Index for common query: all payouts for an investor, newest first
CREATE INDEX idx_payouts_investor_date
  ON public.payouts (investor_id, payout_date DESC);

-- Index for project-level payout queries
CREATE INDEX idx_payouts_project
  ON public.payouts (project_id);
