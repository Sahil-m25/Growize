-- ============================================================
-- MIGRATION 017 — Drop direct-INSERT policies on Edge-Function-only tables
--
-- The Flutter app writes to these tables exclusively via three Edge
-- Functions (create-ticket, reply-ticket, bank-change-request). Each
-- function performs server-side validation that the policies cannot:
--   - 5 tickets per 24h rate limit (create-ticket)
--   - "ticket already resolved?" check (reply-ticket)
--   - 7-day cooldown on pending bank changes (bank-change-request)
--   - account_masked must already be masked (bank-change-request)
-- ...plus an ops-notification email on every write.
--
-- Today the app uses RLS-bound inserts (the policies allow them when
-- investor_id = auth.uid()). After 2026-04-27's redeploy of the three
-- functions to service-role inserts, the RLS policies are redundant.
-- We drop them so a hand-crafted PostgREST POST cannot bypass the
-- rate limits, cooldowns, or ops emails by going directly to the table.
--
-- Reversible:
--   CREATE POLICY "support_tickets: create own ticket" ON public.support_tickets
--     FOR INSERT WITH CHECK (investor_id = (SELECT auth.uid()));
--   CREATE POLICY "ticket_messages: insert own investor message" ON public.ticket_messages
--     FOR INSERT WITH CHECK (
--       sender_type = 'investor' AND
--       ticket_id IN (SELECT id FROM public.support_tickets WHERE investor_id = (SELECT auth.uid()))
--     );
--   CREATE POLICY "bank_change_requests: create own request" ON public.bank_change_requests
--     FOR INSERT WITH CHECK (investor_id = (SELECT auth.uid()));
-- ============================================================

DROP POLICY IF EXISTS "support_tickets: create own ticket"           ON public.support_tickets;
DROP POLICY IF EXISTS "ticket_messages: insert own investor message" ON public.ticket_messages;
DROP POLICY IF EXISTS "bank_change_requests: create own request"     ON public.bank_change_requests;

-- Sanity comment so anyone scanning the schema knows why these tables
-- have SELECT but not INSERT policies for investors.
COMMENT ON TABLE public.support_tickets IS
  'Lightweight ticket system. Staff respond via Supabase Studio. '
  'Investors create tickets ONLY via the create-ticket Edge Function — '
  'no direct INSERT policy. Sufficient for 50-500 users.';

COMMENT ON TABLE public.ticket_messages IS
  'Ticket reply thread. Investors insert ONLY via the reply-ticket '
  'Edge Function (which checks ticket ownership and resolved status). '
  'Staff insert via Supabase Studio (service-role bypasses RLS).';

COMMENT ON TABLE public.bank_change_requests IS
  'Bank change requests. ARL staff verify and update Zoho CRM manually. '
  'Investors submit ONLY via the bank-change-request Edge Function '
  '(which enforces a 7-day cooldown and an already-masked input check).';
