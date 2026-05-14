-- ============================================================
-- MIGRATION 034 — projects_public view (S-002 remediation)
--
-- Audit finding S-002 (docs/security_audit_2026-05-13.md): all client
-- queries against `public.projects` use `.select()` with no column
-- list, so PostgREST returns every column — including
-- `latitude` / `longitude` — to every authenticated marketplace
-- viewer. The LocationScreen privacy policy is that raw coords never
-- leave the screen; the marketplace path violates that.
--
-- Fix: introduce a `public.projects_public` view that lists every
-- safe-to-expose column explicitly and OMITS `latitude` / `longitude`.
-- Client repositories (marketplace, explore, my-projects, project-by-
-- id) read from the view. Future screens that legitimately need raw
-- coords MUST query `public.projects` directly and document why in
-- the screen file.
--
-- Notes:
--   * View is SECURITY INVOKER — same posture migration 015 took for
--     portfolio_summary. RLS on `public.projects` (migration 021)
--     scopes rows to the calling user.
--   * Allowlist not denylist: any new column added to `public.projects`
--     is invisible through this view until it is added below. That is
--     intentional — every new column gets a deliberate exposure
--     decision instead of leaking on schema drift.
--   * The leading `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` block is
--     idempotent. It's there because earlier migrations on `main`
--     (and Supabase Studio-level edits) added the marketplace/
--     subscription columns that this branch's migration history
--     doesn't yet contain. On a DB that already has them the ADDs are
--     no-ops; on a stale DB they back-fill so the view definition
--     below compiles cleanly.
-- ============================================================

-- 1) Idempotent backfill of columns the view references but that may
--    not be defined in this branch's migration sequence.
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS description            TEXT,
  ADD COLUMN IF NOT EXISTS tagline                TEXT,
  ADD COLUMN IF NOT EXISTS subscription_deadline  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_listed_in_marketplace BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS marketplace_sort_order INT,
  ADD COLUMN IF NOT EXISTS marketplace_image      TEXT;

-- 2) Create the privacy-scoped view. Drop+recreate (instead of
--    CREATE OR REPLACE) so column reordering or removals are safe.
DROP VIEW IF EXISTS public.projects_public;

CREATE VIEW public.projects_public
  WITH (security_invoker = on) AS
SELECT
  id,
  zoho_llp_id,
  name,
  tier,
  llp_status,
  llp_owner,
  incorporation_no,
  gst,
  pan,
  -- Coarse location (city/state/country level) is OK to expose; the
  -- raw `latitude` / `longitude` columns on the underlying table are
  -- intentionally NOT projected here. See S-002.
  address_line1,
  city,
  state,
  pincode,
  country,
  -- Financials
  total_units,
  units_issued,
  units_available,
  price_per_unit,
  total_project_cost,
  total_ticket_size,
  -- Farm details
  acreage_acres,
  annual_yield_pct,
  launch_year,
  -- Insurance
  insurance_provider,
  insurance_policy_no,
  insurance_expiry_date,
  insured_amount,
  -- SPOC
  spoc1_name,
  spoc1_phone,
  spoc2_name,
  spoc2_phone,
  -- App display
  cover_image_path,
  color_hex,
  accent_hex,
  description,
  -- Marketplace
  tagline,
  subscription_deadline,
  is_listed_in_marketplace,
  marketplace_sort_order,
  marketplace_image,
  -- Sync observability
  last_synced_at,
  -- Timestamps
  updated_at
FROM public.projects;

COMMENT ON VIEW public.projects_public IS
  'Privacy-scoped projection of public.projects for client consumption. '
  'SECURITY INVOKER — relies on RLS policies on public.projects to '
  'scope visibility. Intentionally omits latitude/longitude per '
  'docs/security_audit_2026-05-13.md S-002. Any new column on '
  'public.projects requires a deliberate decision before being added '
  'to this SELECT list.';

GRANT SELECT ON public.projects_public TO authenticated;

-- Verification (run manually post-apply, expected output noted):
--   SELECT column_name FROM information_schema.columns
--     WHERE table_schema='public' AND table_name='projects_public'
--     ORDER BY ordinal_position;
--   -- 'latitude' and 'longitude' MUST NOT appear in the result.
--
--   SELECT reloptions FROM pg_class
--     WHERE relname='projects_public' AND relkind='v';
--   -- Must contain 'security_invoker=on'.
