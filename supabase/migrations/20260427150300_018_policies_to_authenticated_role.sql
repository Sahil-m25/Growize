-- Migration 018: Convert all public-role policies to authenticated
-- Skip: app_config: public read (intentionally anon), deny policies

-- bank_change_requests: read own rows
DROP POLICY IF EXISTS "bank_change_requests: read own rows" ON public.bank_change_requests;
CREATE POLICY "bank_change_requests: read own rows"
  ON public.bank_change_requests FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- crops: via investor units
DROP POLICY IF EXISTS "crops: via investor units" ON public.crops;
CREATE POLICY "crops: via investor units"
  ON public.crops FOR SELECT
  TO authenticated
  USING (project_id IN (
    SELECT investor_units.project_id
    FROM investor_units
    WHERE investor_units.investor_id = (SELECT auth.uid())
  ));

-- documents: read own rows
DROP POLICY IF EXISTS "documents: read own rows" ON public.documents;
CREATE POLICY "documents: read own rows"
  ON public.documents FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- gallery_photos: via investor units
DROP POLICY IF EXISTS "gallery_photos: via investor units" ON public.gallery_photos;
CREATE POLICY "gallery_photos: via investor units"
  ON public.gallery_photos FOR SELECT
  TO authenticated
  USING (project_id IN (
    SELECT investor_units.project_id
    FROM investor_units
    WHERE investor_units.investor_id = (SELECT auth.uid())
  ));

-- investor_units: read own rows
DROP POLICY IF EXISTS "investor_units: read own rows" ON public.investor_units;
CREATE POLICY "investor_units: read own rows"
  ON public.investor_units FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- investors: read own row
DROP POLICY IF EXISTS "investors: read own row" ON public.investors;
CREATE POLICY "investors: read own row"
  ON public.investors FOR SELECT
  TO authenticated
  USING (id = (SELECT auth.uid()));

-- notifications: read own rows
DROP POLICY IF EXISTS "notifications: read own rows" ON public.notifications;
CREATE POLICY "notifications: read own rows"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- notifications: mark own as read
DROP POLICY IF EXISTS "notifications: mark own as read" ON public.notifications;
CREATE POLICY "notifications: mark own as read"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (investor_id = (SELECT auth.uid()))
  WITH CHECK (investor_id = (SELECT auth.uid()));

-- payouts: read own rows
DROP POLICY IF EXISTS "payouts: read own rows" ON public.payouts;
CREATE POLICY "payouts: read own rows"
  ON public.payouts FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- project_phases: via investor units
DROP POLICY IF EXISTS "project_phases: via investor units" ON public.project_phases;
CREATE POLICY "project_phases: via investor units"
  ON public.project_phases FOR SELECT
  TO authenticated
  USING (project_id IN (
    SELECT investor_units.project_id
    FROM investor_units
    WHERE investor_units.investor_id = (SELECT auth.uid())
  ));

-- projects: visible to investors with units (keep as authenticated, not public)
DROP POLICY IF EXISTS "projects: visible to investors with units" ON public.projects;
CREATE POLICY "projects: visible to investors with units"
  ON public.projects FOR SELECT
  TO authenticated
  USING (id IN (
    SELECT investor_units.project_id
    FROM investor_units
    WHERE investor_units.investor_id = (SELECT auth.uid())
  ));

-- support_tickets: read own rows
DROP POLICY IF EXISTS "support_tickets: read own rows" ON public.support_tickets;
CREATE POLICY "support_tickets: read own rows"
  ON public.support_tickets FOR SELECT
  TO authenticated
  USING (investor_id = (SELECT auth.uid()));

-- ticket_messages: read via own tickets
DROP POLICY IF EXISTS "ticket_messages: read via own tickets" ON public.ticket_messages;
CREATE POLICY "ticket_messages: read via own tickets"
  ON public.ticket_messages FOR SELECT
  TO authenticated
  USING (ticket_id IN (
    SELECT support_tickets.id
    FROM support_tickets
    WHERE support_tickets.investor_id = (SELECT auth.uid())
  ));
