
-- ============================================================
-- MIGRATION 009 — ROW LEVEL SECURITY (RLS)
-- Every table is locked down. Investors see ONLY their own data.
-- No table is left without RLS enabled.
-- Service role (Edge Functions) bypasses RLS — by design.
-- Tested rule: log in as investor A, query investor B → 0 rows.
-- ============================================================

-- Enable RLS on every table
ALTER TABLE public.investors             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investor_units        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payouts               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_phases        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crops                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gallery_photos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_change_requests  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_config            ENABLE ROW LEVEL SECURITY;

-- -------------------------------------------------------
-- INVESTORS: see only own row
-- -------------------------------------------------------
CREATE POLICY "investors: read own row"
  ON public.investors FOR SELECT
  USING (id = auth.uid());

-- -------------------------------------------------------
-- PROJECTS: visible only if investor has units in it
-- (No direct project browsing — must own units to see)
-- -------------------------------------------------------
CREATE POLICY "projects: visible to investors with units"
  ON public.projects FOR SELECT
  USING (
    id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- INVESTOR UNITS: own allocations only
-- -------------------------------------------------------
CREATE POLICY "investor_units: read own rows"
  ON public.investor_units FOR SELECT
  USING (investor_id = auth.uid());

-- -------------------------------------------------------
-- PAYOUTS: own payouts only
-- -------------------------------------------------------
CREATE POLICY "payouts: read own rows"
  ON public.payouts FOR SELECT
  USING (investor_id = auth.uid());

-- -------------------------------------------------------
-- PROJECT PHASES: only for projects investor has units in
-- -------------------------------------------------------
CREATE POLICY "project_phases: via investor units"
  ON public.project_phases FOR SELECT
  USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- CROPS: only for projects investor has units in
-- -------------------------------------------------------
CREATE POLICY "crops: via investor units"
  ON public.crops FOR SELECT
  USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- GALLERY PHOTOS: only for investor's projects
-- -------------------------------------------------------
CREATE POLICY "gallery_photos: via investor units"
  ON public.gallery_photos FOR SELECT
  USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- DOCUMENTS: own documents only
-- -------------------------------------------------------
CREATE POLICY "documents: read own rows"
  ON public.documents FOR SELECT
  USING (investor_id = auth.uid());

-- -------------------------------------------------------
-- NOTIFICATIONS: own notifications only
-- Investor can mark as read (UPDATE read_at)
-- -------------------------------------------------------
CREATE POLICY "notifications: read own rows"
  ON public.notifications FOR SELECT
  USING (investor_id = auth.uid());

CREATE POLICY "notifications: mark own as read"
  ON public.notifications FOR UPDATE
  USING (investor_id = auth.uid())
  WITH CHECK (investor_id = auth.uid());

-- -------------------------------------------------------
-- SUPPORT TICKETS: own tickets only
-- Investor can INSERT (raise) and SELECT (read their tickets)
-- -------------------------------------------------------
CREATE POLICY "support_tickets: read own rows"
  ON public.support_tickets FOR SELECT
  USING (investor_id = auth.uid());

CREATE POLICY "support_tickets: create own ticket"
  ON public.support_tickets FOR INSERT
  WITH CHECK (investor_id = auth.uid());

-- -------------------------------------------------------
-- TICKET MESSAGES: only messages on own tickets
-- Investor can INSERT their own messages (sender_type must be 'investor')
-- -------------------------------------------------------
CREATE POLICY "ticket_messages: read via own tickets"
  ON public.ticket_messages FOR SELECT
  USING (
    ticket_id IN (
      SELECT id FROM public.support_tickets
      WHERE investor_id = auth.uid()
    )
  );

CREATE POLICY "ticket_messages: insert own investor message"
  ON public.ticket_messages FOR INSERT
  WITH CHECK (
    sender_type = 'investor' AND
    ticket_id IN (
      SELECT id FROM public.support_tickets
      WHERE investor_id = auth.uid()
    )
  );

-- -------------------------------------------------------
-- BANK CHANGE REQUESTS: own requests only
-- Investor can INSERT and SELECT
-- -------------------------------------------------------
CREATE POLICY "bank_change_requests: read own rows"
  ON public.bank_change_requests FOR SELECT
  USING (investor_id = auth.uid());

CREATE POLICY "bank_change_requests: create own request"
  ON public.bank_change_requests FOR INSERT
  WITH CHECK (investor_id = auth.uid());

-- -------------------------------------------------------
-- WEBHOOK LOG: no investor access — service role only
-- (No SELECT policy = authenticated users get 0 rows)
-- -------------------------------------------------------
-- No policies added. RLS enabled = blocked for all JWT users.
-- Edge Functions use service_role key → bypass RLS.

-- -------------------------------------------------------
-- APP CONFIG: public read, no write for investors
-- -------------------------------------------------------
CREATE POLICY "app_config: public read"
  ON public.app_config FOR SELECT
  TO anon, authenticated
  USING (true);
