
-- ============================================================
-- MIGRATION 004 — PROJECT PHASES & CROPS
-- No Zoho module exists yet for these.
-- Seeded manually via Supabase Studio by ARL staff.
-- When a Zoho module is created later, zoho-crm-webhook
--   can upsert into these tables using zoho_phase_id /
--   zoho_crop_id — schema already has the column ready.
-- ============================================================

-- -------------------------------------------------------
-- PROJECT PHASES
-- Timeline milestones shown in the app's project detail view.
-- sub_items holds nested checklist items (no extra table needed).
-- -------------------------------------------------------
CREATE TABLE public.project_phases (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_phase_id   TEXT UNIQUE,          -- future: Zoho module ID when that module is built

  phase_name      TEXT NOT NULL,        -- e.g. "Land Preparation", "Planting", "First Harvest"
  status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('done','current','pending')),
  phase_date      DATE,                 -- target or completion date
  sort_order      INT NOT NULL DEFAULT 0,

  -- Nested checklist items stored as JSONB array
  -- Format: [{ "label": "1.1", "detail": "Soil pH analysis complete", "date": "2026-02-20", "done": true }]
  sub_items       JSONB NOT NULL DEFAULT '[]',

  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.project_phases IS
  'Project timeline milestones. Manually seeded by ARL staff. '
  'sub_items JSONB holds nested checklist steps — no extra table.';

CREATE INDEX idx_phases_project_order
  ON public.project_phases (project_id, sort_order ASC);

-- -------------------------------------------------------
-- CROPS
-- Crop cycles per project. is_current=TRUE = active crop.
-- Historical rows kept for the "crop history" toggle in the app.
-- Only one crop per project should have is_current=TRUE.
-- -------------------------------------------------------
CREATE TABLE public.crops (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  zoho_crop_id    TEXT UNIQUE,          -- future: Zoho module ID

  name            TEXT NOT NULL,        -- e.g. "Alphonso Mango", "Teak"
  emoji           TEXT DEFAULT '🌱',
  start_date      DATE,
  end_date        DATE,
  harvest_date    DATE,
  progress_pct    INT NOT NULL DEFAULT 0
                    CHECK (progress_pct BETWEEN 0 AND 100),
  is_current      BOOLEAN NOT NULL DEFAULT FALSE,
  revenue         NUMERIC(14,2),        -- filled post-harvest

  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.crops IS
  'Crop cycles per project. is_current=TRUE marks active crop. Historical rows kept.';

-- Partial unique index: only one current crop per project
CREATE UNIQUE INDEX idx_crops_one_current_per_project
  ON public.crops (project_id)
  WHERE is_current = TRUE;
