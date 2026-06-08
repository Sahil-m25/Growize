
-- ============================================================
-- MIGRATION 007 — OPERATIONAL TABLES
-- webhook_log: audit trail of every incoming webhook
-- app_config:  key-value store for force-update and feature flags
-- Both tables are service-role only — no investor RLS needed.
-- ============================================================

-- -------------------------------------------------------
-- WEBHOOK LOG
-- Every incoming webhook payload is logged before processing.
-- Enables: idempotency checks, replay, debugging, health alerts.
-- Retention: 90 days recommended (set via pg_cron or manual purge).
-- -------------------------------------------------------
CREATE TABLE public.webhook_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  source          TEXT NOT NULL
                    CHECK (source IN ('zoho_crm','zoho_books','gallery_sync','manual')),
  event_type      TEXT,                 -- e.g. "contact_update", "unit_allocation_create"
  zoho_record_id  TEXT,                 -- the CRM/Books record ID in the payload
  idempotency_key TEXT UNIQUE,          -- prevents double-processing on Zoho retry

  payload         JSONB NOT NULL DEFAULT '{}',   -- full raw webhook body
  status          TEXT NOT NULL DEFAULT 'received'
                    CHECK (status IN ('received','processed','failed','duplicate')),
  error_message   TEXT,                 -- populated on status='failed'

  received_at     TIMESTAMPTZ DEFAULT NOW(),
  processed_at    TIMESTAMPTZ
);

COMMENT ON TABLE public.webhook_log IS
  'Audit log for all incoming webhooks. Check idempotency_key before processing. '
  'Purge rows older than 90 days periodically.';

CREATE INDEX idx_webhook_log_source_received
  ON public.webhook_log (source, received_at DESC);

CREATE INDEX idx_webhook_log_status
  ON public.webhook_log (status)
  WHERE status = 'failed';

-- -------------------------------------------------------
-- APP CONFIG
-- Key-value store read by Flutter on launch.
-- Controls: force-update, maintenance mode, feature flags.
-- No RLS — public read, service-role write.
-- -------------------------------------------------------
CREATE TABLE public.app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.app_config IS
  'App-level config flags. Read publicly on launch. Written by ARL staff via Supabase Studio.';

-- Seed default values
INSERT INTO public.app_config (key, value) VALUES
  ('min_app_version',    '1.0.0'),
  ('latest_app_version', '1.0.0'),
  ('maintenance_mode',   'false'),
  ('maintenance_message',''),
  ('android_store_url',  ''),
  ('ios_store_url',      '');
