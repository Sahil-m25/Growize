-- ============================================================
-- MIGRATION 053 — project_phases: started_at & completed_at
-- ------------------------------------------------------------
-- Investor-facing UX feedback: the Phase Timeline on the
-- Project Detail screen shows the current phase, but provides
-- no visual hint of *when* prior phases completed or *when*
-- the current phase started. For long-running projects (e.g.
-- Pineapple LLP launched Jun-2024) the timeline reads as a
-- frozen dot, even though months of work are done behind it.
--
-- We already have `phase_date DATE` from migration 004, but a
-- single date can't carry both "started" and "completed" for
-- a single row (the current phase wants started; done phases
-- want completed). Splitting into two TIMESTAMPTZ columns lets
-- the app render:
--   * "Completed 12 Mar 2026" on done nodes
--   * "In progress — started 5 May 2026" on the current node
-- without losing the old column (back-compat for any seeded
-- rows that still only set `phase_date`).
--
-- Both columns are nullable. The app's read-path falls back
-- to `phase_date` when started/completed are NULL.
--
-- RLS is unchanged: the existing `project_phases: via investor
-- units` policy (migration 018) already gates SELECT to
-- investors-with-allocation, so adding columns is transparent.
-- ============================================================

ALTER TABLE public.project_phases
  ADD COLUMN IF NOT EXISTS started_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.project_phases.started_at IS
  'When work on this phase actually began. Used by the app to '
  'render "In progress — started <date>" on the current node. '
  'Nullable: legacy rows fall back to phase_date.';

COMMENT ON COLUMN public.project_phases.completed_at IS
  'When this phase was signed off as done. Used by the app to '
  'render "Completed <date>" on done nodes. Nullable: legacy '
  'rows fall back to phase_date.';
