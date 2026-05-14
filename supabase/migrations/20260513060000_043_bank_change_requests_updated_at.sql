-- ============================================================
-- 043: Add bank_change_requests.updated_at (DEF-11)
-- ============================================================
-- Migration 010 created trigger trg_bank_change_requests_updated_at
-- which calls public.set_updated_at() to maintain an updated_at
-- column — but migration 006 never created the column on this
-- table. Every UPDATE therefore fails with
--   record "new" has no field "updated_at"
-- which blocked ops from transitioning bank-change requests through
-- pending → approved/rejected, and prevented the status-change
-- notification trigger shipped in migration 041 from ever firing.
--
-- Fix: add the column. Option A is correct here because every other
-- table that has the trigger (investors, projects, investor_units,
-- payouts, project_phases, crops, support_tickets, app_config)
-- already has updated_at — this row is the schema outlier, not the
-- trigger.
-- ============================================================

ALTER TABLE public.bank_change_requests
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMENT ON COLUMN public.bank_change_requests.updated_at IS
  'Maintained by trg_bank_change_requests_updated_at (set_updated_at). Drives ops status-change notifications.';
