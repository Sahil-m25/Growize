-- ============================================================
-- MIGRATION 023 — last_synced_at observability columns
--
-- Adds a per-row sync timestamp to every CRM-mirrored table.
-- Set on every successful upsert by:
--   * the zoho-crm-webhook function (push path), and
--   * the zoho-reconcile-daily function (pull path).
--
-- Closes DEF-2026-05-07-01: TC-SYNC-001-01 / D-01 referenced
-- llps.last_synced_at which never existed. With this migration the
-- column is real on llps + projects + investors + investor_units, and
-- the daily UAT freshness check can compute
-- max(now() - last_synced_at) per table.
--
-- updated_at remains the row's last *write* time (any source). The
-- new column is specifically the last time we confirmed the Supabase
-- row matches the upstream Zoho CRM record. They diverge when an
-- admin edits a Supabase row directly without a corresponding CRM
-- update.
-- ============================================================

ALTER TABLE public.llps
  ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;

ALTER TABLE public.investors
  ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;

ALTER TABLE public.investor_units
  ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;

-- Index for the freshness check (max(last_synced_at) … WHERE …).
CREATE INDEX IF NOT EXISTS idx_llps_last_synced_at
  ON public.llps (last_synced_at DESC);

CREATE INDEX IF NOT EXISTS idx_projects_last_synced_at
  ON public.projects (last_synced_at DESC);

CREATE INDEX IF NOT EXISTS idx_investors_last_synced_at
  ON public.investors (last_synced_at DESC);

CREATE INDEX IF NOT EXISTS idx_investor_units_last_synced_at
  ON public.investor_units (last_synced_at DESC);

-- Backfill the existing rows to their current updated_at so the first
-- staleness check after deploy doesn't immediately scream. The
-- reconcile job will overwrite this with the real value on its next
-- pass.
UPDATE public.llps           SET last_synced_at = updated_at WHERE last_synced_at IS NULL;
UPDATE public.projects       SET last_synced_at = updated_at WHERE last_synced_at IS NULL;
UPDATE public.investors      SET last_synced_at = updated_at WHERE last_synced_at IS NULL;
UPDATE public.investor_units SET last_synced_at = updated_at WHERE last_synced_at IS NULL;

COMMENT ON COLUMN public.llps.last_synced_at IS
  'Last time this row was written by a Zoho sync (webhook or reconcile). '
  'NULL means the row has never been touched by the sync pipeline.';
COMMENT ON COLUMN public.projects.last_synced_at IS
  'Last time this row was written by a Zoho sync (webhook or reconcile).';
COMMENT ON COLUMN public.investors.last_synced_at IS
  'Last time this row was written by a Zoho sync (webhook or reconcile).';
COMMENT ON COLUMN public.investor_units.last_synced_at IS
  'Last time this row was written by a Zoho sync (webhook or reconcile).';

-- ── sync_alerts table ────────────────────────────────────────────
-- Stale-data observability. The sync-stale-alert cron writes one row
-- per check-cycle whenever any monitored table's max(last_synced_at)
-- exceeds the threshold. health-check reads recent rows to surface
-- ops alerts.
CREATE TABLE IF NOT EXISTS public.sync_alerts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name      TEXT NOT NULL,
  max_synced_at   TIMESTAMPTZ,
  age_seconds     INTEGER NOT NULL,
  threshold_secs  INTEGER NOT NULL,
  detail          TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_alerts_created
  ON public.sync_alerts (created_at DESC);

COMMENT ON TABLE public.sync_alerts IS
  'Append-only log of CRM->Supabase sync staleness incidents. '
  'Service-role write; authenticated read for ops dashboards. '
  'Purge entries older than 30 days periodically.';

-- ── sync_status view ─────────────────────────────────────────────
-- One-row-per-table summary of current sync freshness. Used by the
-- daily UAT runbook (D-01) and health-check.
CREATE OR REPLACE VIEW public.sync_status AS
SELECT 'llps'::text           AS table_name, COUNT(*)::int AS rows, MAX(last_synced_at) AS max_synced_at FROM public.llps
UNION ALL
SELECT 'projects'::text       AS table_name, COUNT(*)::int AS rows, MAX(last_synced_at) AS max_synced_at FROM public.projects
UNION ALL
SELECT 'investors'::text      AS table_name, COUNT(*)::int AS rows, MAX(last_synced_at) AS max_synced_at FROM public.investors
UNION ALL
SELECT 'investor_units'::text AS table_name, COUNT(*)::int AS rows, MAX(last_synced_at) AS max_synced_at FROM public.investor_units;

COMMENT ON VIEW public.sync_status IS
  'Per-table sync freshness snapshot. Read by health-check and the '
  'daily UAT D-01 case (max(last_synced_at) within last 30 minutes).';
