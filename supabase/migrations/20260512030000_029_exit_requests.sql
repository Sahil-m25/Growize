-- ============================================================
-- MIGRATION 029 — EXIT REQUESTS
-- Backs the ExitScreen "Request Exit" CTA. Investor taps the button
-- once their lock-in has ended → row is written here and ARL ops
-- works the queue out of band. The investment under exit is an
-- `investor_units` row (one row per allocation).
--
-- Duplicate guard is at the DB level: a partial unique index on
-- (investor_unit_id) WHERE status='pending' makes it race-safe — two
-- simultaneous taps cannot both create pending rows for the same
-- investment. Caller catches 23505 and surfaces "already submitted".
-- ============================================================

CREATE TABLE public.exit_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_unit_id  UUID NOT NULL REFERENCES public.investor_units(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason            TEXT,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','approved','rejected','settled')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at       TIMESTAMPTZ
);

COMMENT ON TABLE public.exit_requests IS
  'Investor exit requests against a specific investor_units row. ARL '
  'staff work the queue via service_role (Studio / future Edge '
  'Function); investors only read their own rows.';

CREATE INDEX idx_exit_requests_user_created
  ON public.exit_requests (user_id, created_at DESC);

-- DB-level race-safe duplicate guard: at most one pending request per
-- investor_unit at any time. Resolved (approved/rejected/settled) rows
-- don't count, so a rejected request can be re-filed.
CREATE UNIQUE INDEX uniq_exit_requests_pending_unit
  ON public.exit_requests (investor_unit_id)
  WHERE status = 'pending';

ALTER TABLE public.exit_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exit_requests: select own"
  ON public.exit_requests FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "exit_requests: insert own"
  ON public.exit_requests FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

GRANT SELECT, INSERT ON public.exit_requests TO authenticated;
