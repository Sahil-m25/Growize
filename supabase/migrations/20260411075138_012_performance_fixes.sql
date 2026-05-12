
-- ============================================================
-- MIGRATION 012 — PERFORMANCE FIXES
-- 1. RLS policies: wrap auth.uid() in (SELECT auth.uid())
--    so Postgres evaluates it once per query, not once per row.
-- 2. Add missing indexes on foreign key columns.
-- ============================================================

-- -------------------------------------------------------
-- Drop all existing RLS policies and recreate optimised
-- -------------------------------------------------------

-- INVESTORS
DROP POLICY "investors: read own row" ON public.investors;
CREATE POLICY "investors: read own row" ON public.investors
  FOR SELECT USING (id = (SELECT auth.uid()));

-- PROJECTS
DROP POLICY "projects: visible to investors with units" ON public.projects;
CREATE POLICY "projects: visible to investors with units" ON public.projects
  FOR SELECT USING (
    id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- INVESTOR UNITS
DROP POLICY "investor_units: read own rows" ON public.investor_units;
CREATE POLICY "investor_units: read own rows" ON public.investor_units
  FOR SELECT USING (investor_id = (SELECT auth.uid()));

-- PAYOUTS
DROP POLICY "payouts: read own rows" ON public.payouts;
CREATE POLICY "payouts: read own rows" ON public.payouts
  FOR SELECT USING (investor_id = (SELECT auth.uid()));

-- PROJECT PHASES
DROP POLICY "project_phases: via investor units" ON public.project_phases;
CREATE POLICY "project_phases: via investor units" ON public.project_phases
  FOR SELECT USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- CROPS
DROP POLICY "crops: via investor units" ON public.crops;
CREATE POLICY "crops: via investor units" ON public.crops
  FOR SELECT USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- GALLERY PHOTOS
DROP POLICY "gallery_photos: via investor units" ON public.gallery_photos;
CREATE POLICY "gallery_photos: via investor units" ON public.gallery_photos
  FOR SELECT USING (
    project_id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- DOCUMENTS
DROP POLICY "documents: read own rows" ON public.documents;
CREATE POLICY "documents: read own rows" ON public.documents
  FOR SELECT USING (investor_id = (SELECT auth.uid()));

-- NOTIFICATIONS
DROP POLICY "notifications: read own rows" ON public.notifications;
DROP POLICY "notifications: mark own as read" ON public.notifications;
CREATE POLICY "notifications: read own rows" ON public.notifications
  FOR SELECT USING (investor_id = (SELECT auth.uid()));
CREATE POLICY "notifications: mark own as read" ON public.notifications
  FOR UPDATE
  USING (investor_id = (SELECT auth.uid()))
  WITH CHECK (investor_id = (SELECT auth.uid()));

-- SUPPORT TICKETS
DROP POLICY "support_tickets: read own rows" ON public.support_tickets;
DROP POLICY "support_tickets: create own ticket" ON public.support_tickets;
CREATE POLICY "support_tickets: read own rows" ON public.support_tickets
  FOR SELECT USING (investor_id = (SELECT auth.uid()));
CREATE POLICY "support_tickets: create own ticket" ON public.support_tickets
  FOR INSERT WITH CHECK (investor_id = (SELECT auth.uid()));

-- TICKET MESSAGES
DROP POLICY "ticket_messages: read via own tickets" ON public.ticket_messages;
DROP POLICY "ticket_messages: insert own investor message" ON public.ticket_messages;
CREATE POLICY "ticket_messages: read via own tickets" ON public.ticket_messages
  FOR SELECT USING (
    ticket_id IN (
      SELECT id FROM public.support_tickets
      WHERE investor_id = (SELECT auth.uid())
    )
  );
CREATE POLICY "ticket_messages: insert own investor message" ON public.ticket_messages
  FOR INSERT WITH CHECK (
    sender_type = 'investor' AND
    ticket_id IN (
      SELECT id FROM public.support_tickets
      WHERE investor_id = (SELECT auth.uid())
    )
  );

-- BANK CHANGE REQUESTS
DROP POLICY "bank_change_requests: read own rows" ON public.bank_change_requests;
DROP POLICY "bank_change_requests: create own request" ON public.bank_change_requests;
CREATE POLICY "bank_change_requests: read own rows" ON public.bank_change_requests
  FOR SELECT USING (investor_id = (SELECT auth.uid()));
CREATE POLICY "bank_change_requests: create own request" ON public.bank_change_requests
  FOR INSERT WITH CHECK (investor_id = (SELECT auth.uid()));

-- -------------------------------------------------------
-- Missing FK indexes
-- -------------------------------------------------------

-- investor_units: investor_id and project_id
CREATE INDEX idx_investor_units_investor_id ON public.investor_units (investor_id);
CREATE INDEX idx_investor_units_project_id  ON public.investor_units (project_id);

-- payouts: allocation_id
CREATE INDEX idx_payouts_allocation_id ON public.payouts (allocation_id);

-- documents: project_id (investor_id already indexed via idx_documents_investor)
CREATE INDEX idx_documents_project_id ON public.documents (project_id);

-- support_tickets: project_id (investor_id covered by idx_tickets_investor_status)
CREATE INDEX idx_support_tickets_project_id ON public.support_tickets (project_id);

-- bank_change_requests: investor_id
CREATE INDEX idx_bank_change_requests_investor_id ON public.bank_change_requests (investor_id);
