
-- ============================================================
-- MIGRATION 006 — NOTIFICATIONS, SUPPORT & BANK CHANGE
-- All three are Supabase-native (no Zoho source).
-- Notifications: in-app activity feed only (no push for now).
--   When FCM is added later → add device_tokens table as a
--   new migration + notify-push Edge Function. Zero changes here.
-- Support tickets: ARL staff respond via Supabase Studio.
-- Bank change requests: human-in-the-loop via ARL staff.
-- ============================================================

-- -------------------------------------------------------
-- NOTIFICATIONS (in-app activity feed)
-- Created by: Edge Functions and DB triggers
-- NOT for push notifications yet — in-app read only
-- FCM/device_tokens added later as a separate migration
-- -------------------------------------------------------
CREATE TABLE public.notifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id     UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,

  type            TEXT NOT NULL
                    CHECK (type IN ('payout','photo','ticket','reminder','milestone')),
  title           TEXT NOT NULL,
  body            TEXT,

  -- Structured metadata for deep linking in Flutter
  -- payout:    { "project_id": "...", "amount": 12400, "utr": "UTIB000123" }
  -- photo:     { "project_id": "...", "photo_count": 5 }
  -- ticket:    { "ticket_id": "...", "status": "resolved" }
  -- milestone: { "project_id": "...", "phase_name": "First Harvest" }
  -- reminder:  { "project_id": "...", "amount_due": 50000 }
  metadata        JSONB NOT NULL DEFAULT '{}',

  read_at         TIMESTAMPTZ,           -- NULL = unread
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.notifications IS
  'In-app activity feed. Push notification support (device_tokens + notify-push) '
  'added as a future migration — no changes needed to this table.';

CREATE INDEX idx_notifications_investor_unread
  ON public.notifications (investor_id, created_at DESC)
  WHERE read_at IS NULL;

-- -------------------------------------------------------
-- SUPPORT TICKETS
-- Investor raises in app → stored here → ARL staff
--   respond via Supabase Studio → investor sees reply in app.
-- -------------------------------------------------------
CREATE TABLE public.support_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id     UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,
  project_id      UUID REFERENCES public.projects(id) ON DELETE SET NULL,

  category        TEXT NOT NULL DEFAULT 'general'
                    CHECK (category IN ('payout','documents','general','bank_change','exit_request')),
  subject         TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','in_progress','resolved')),

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.support_tickets IS
  'Lightweight ticket system. Staff respond via Supabase Studio. '
  'Sufficient for 50-500 users (<20 tickets/month estimated).';

CREATE INDEX idx_tickets_investor_status
  ON public.support_tickets (investor_id, status, created_at DESC);

-- -------------------------------------------------------
-- TICKET MESSAGES (thread)
-- sender_type distinguishes investor messages from staff replies.
-- -------------------------------------------------------
CREATE TABLE public.ticket_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id       UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_type     TEXT NOT NULL CHECK (sender_type IN ('investor','staff')),
  body            TEXT NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ticket_messages_ticket
  ON public.ticket_messages (ticket_id, created_at ASC);

-- -------------------------------------------------------
-- BANK CHANGE REQUESTS
-- Investor submits new bank details (masked) in app.
-- ARL verifies manually → updates Zoho CRM → webhook
--   updates investors table. Human-in-the-loop by design.
-- 7-day cooldown enforced in the Edge Function, not here.
-- -------------------------------------------------------
CREATE TABLE public.bank_change_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investor_id         UUID NOT NULL REFERENCES public.investors(id) ON DELETE CASCADE,

  -- New details submitted by investor (masked)
  new_bank_name       TEXT,
  new_account_masked  TEXT,             -- "XXXX-XXXX-1234" — last 4 digits only
  new_ifsc            TEXT,
  new_holder_name     TEXT,

  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','rejected')),
  notes               TEXT,             -- ARL staff resolution notes
  requested_at        TIMESTAMPTZ DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ
);

COMMENT ON TABLE public.bank_change_requests IS
  'Bank change requests. ARL staff verify and update Zoho CRM manually. '
  'Supabase is updated via CRM webhook after approval.';
