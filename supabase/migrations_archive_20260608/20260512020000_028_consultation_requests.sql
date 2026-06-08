-- ============================================================
-- MIGRATION 028 — CONSULTATION REQUESTS
-- Backs the ExploreScreen "Request Consultation" CTA. Investor taps
-- the button on a marketplace listing → row gets written here and
-- ARL ops follows up out of band. Row is RLS-scoped to the writing
-- user; ARL staff read/update through service_role (Studio / Edge
-- Functions), per the existing staff-access pattern.
-- ============================================================

CREATE TABLE public.consultation_requests (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  project_id       UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  units_requested  INT,
  message          TEXT,
  status           TEXT NOT NULL DEFAULT 'new'
                     CHECK (status IN ('new','contacted','closed')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.consultation_requests IS
  'Marketplace consultation requests from the Explore tab. ARL staff '
  'work the queue via Supabase Studio; investors only read their own '
  'rows.';

CREATE INDEX idx_consultation_user_created
  ON public.consultation_requests (user_id, created_at DESC);

CREATE INDEX idx_consultation_project_status
  ON public.consultation_requests (project_id, status, created_at DESC);

ALTER TABLE public.consultation_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "consultation_requests: select own"
  ON public.consultation_requests FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "consultation_requests: insert own"
  ON public.consultation_requests FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

GRANT SELECT, INSERT ON public.consultation_requests TO authenticated;
