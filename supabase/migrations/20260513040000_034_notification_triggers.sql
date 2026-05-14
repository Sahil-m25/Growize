-- ============================================================
-- MIGRATION 034 — NOTIFICATION TRIGGERS
-- Wires four state transitions to automatic notification inserts
-- so the investor sees an in-app entry without the originating
-- Edge Function / ops user needing to issue a second write.
--
--   (a) investors.kyc_status: pending → verified | rejected
--   (b) exit_requests.status: pending → approved | rejected | settled
--   (c) ticket_messages: new staff reply
--   (d) bank_change_requests.status: pending → approved | rejected
--
-- All four functions run SECURITY DEFINER so they can insert
-- into `notifications` regardless of the calling role (an ops
-- user editing in Supabase Studio, an Edge Function running as
-- service_role, or the investor's own UPDATE on
-- `ticket_messages` via reply-ticket). search_path is pinned
-- to `public, pg_temp` to prevent search-path-hijack attacks
-- via a temp-schema function shadowing.
-- ============================================================

-- 0) Expand notifications.type CHECK to cover new event kinds.
--    Existing values (payout / photo / ticket / reminder /
--    milestone) all stay valid; we add kyc / exit / bank_change.
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN ('payout', 'photo', 'ticket', 'reminder',
             'milestone', 'kyc', 'exit', 'bank_change')
  );

-- 1) KYC status change ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_investor_kyc_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.kyc_status = 'pending'
     AND NEW.kyc_status IN ('verified', 'rejected')
     AND NEW.kyc_status IS DISTINCT FROM OLD.kyc_status THEN
    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.id,
      'kyc',
      CASE WHEN NEW.kyc_status = 'verified'
           THEN 'KYC verified'
           ELSE 'KYC rejected' END,
      CASE WHEN NEW.kyc_status = 'verified'
           THEN 'Your KYC has been verified. Tap to view.'
           ELSE 'Your KYC has been rejected. Please re-submit.' END,
      jsonb_build_object(
        'kyc_status', NEW.kyc_status,
        'previous_status', OLD.kyc_status
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_investor_kyc_status_change
  ON public.investors;
CREATE TRIGGER trg_notify_investor_kyc_status_change
  AFTER UPDATE OF kyc_status ON public.investors
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_investor_kyc_status_change();

-- 2) Exit request status change ------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_exit_request_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_title TEXT;
  v_body  TEXT;
BEGIN
  IF OLD.status = 'pending'
     AND NEW.status IN ('approved', 'rejected', 'settled')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'approved' THEN
        v_title := 'Exit request approved';
        v_body  := 'Your exit request has been approved. Settlement will follow.';
      WHEN 'rejected' THEN
        v_title := 'Exit request rejected';
        v_body  := 'Your exit request has been rejected. Reach out to support for details.';
      ELSE
        v_title := 'Exit settled';
        v_body  := 'Your exit settlement has been processed.';
    END CASE;

    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.user_id,
      'exit',
      v_title,
      v_body,
      jsonb_build_object(
        'exit_request_id', NEW.id,
        'status', NEW.status,
        'investor_unit_id', NEW.investor_unit_id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_exit_request_status_change
  ON public.exit_requests;
CREATE TRIGGER trg_notify_exit_request_status_change
  AFTER UPDATE OF status ON public.exit_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_exit_request_status_change();

-- 3) Ticket reply (staff → investor) -------------------------------------
CREATE OR REPLACE FUNCTION public.notify_ticket_reply()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_investor_id UUID;
  v_short_id    TEXT;
BEGIN
  -- Only fire on replies that are NOT from the ticket's investor.
  -- sender_type CHECK allows ('investor', 'staff'); a staff reply
  -- is the trigger condition. Investor self-replies do not notify.
  IF NEW.sender_type = 'investor' THEN
    RETURN NEW;
  END IF;

  SELECT investor_id INTO v_investor_id
  FROM public.support_tickets
  WHERE id = NEW.ticket_id;

  IF v_investor_id IS NULL THEN
    -- Orphaned reply (ticket deleted between insert + trigger fire).
    -- Nothing to notify; bail without raising.
    RETURN NEW;
  END IF;

  v_short_id := substr(NEW.ticket_id::text, 1, 8);

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  VALUES (
    v_investor_id,
    'ticket',
    'New reply on your ticket',
    'New reply on ticket #' || v_short_id || '.',
    jsonb_build_object(
      'ticket_id', NEW.ticket_id,
      'message_id', NEW.id,
      'sender_type', NEW.sender_type
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_ticket_reply
  ON public.ticket_messages;
CREATE TRIGGER trg_notify_ticket_reply
  AFTER INSERT ON public.ticket_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_ticket_reply();

-- 4) Bank change request status ------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_bank_change_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_title TEXT;
  v_body  TEXT;
BEGIN
  IF OLD.status = 'pending'
     AND NEW.status IN ('approved', 'rejected')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'approved' THEN
      v_title := 'Bank change approved';
      v_body  := 'Your bank account update has been approved and will reflect after the next CRM sync.';
    ELSE
      v_title := 'Bank change rejected';
      v_body  := COALESCE(
        'Your bank account update was rejected. ' || NEW.notes,
        'Your bank account update was rejected. Contact support for details.'
      );
    END IF;

    INSERT INTO public.notifications (investor_id, type, title, body, metadata)
    VALUES (
      NEW.investor_id,
      'bank_change',
      v_title,
      v_body,
      jsonb_build_object(
        'bank_change_request_id', NEW.id,
        'status', NEW.status
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_bank_change_status_change
  ON public.bank_change_requests;
CREATE TRIGGER trg_notify_bank_change_status_change
  AFTER UPDATE OF status ON public.bank_change_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_bank_change_status_change();

-- Grants — explicit so the SECURITY DEFINER functions remain callable
-- only via the trigger system. EXECUTE on public.* defaults to PUBLIC
-- on standard Supabase setups; we revoke direct EXECUTE so the only
-- caller is the trigger context.
REVOKE EXECUTE ON FUNCTION public.notify_investor_kyc_status_change()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_exit_request_status_change()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_ticket_reply()                FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_bank_change_status_change()   FROM PUBLIC;

COMMENT ON FUNCTION public.notify_investor_kyc_status_change() IS
  'Trigger fn: inserts notifications row when investor KYC flips pending→verified|rejected.';
COMMENT ON FUNCTION public.notify_exit_request_status_change() IS
  'Trigger fn: inserts notifications row when exit_request flips pending→approved|rejected|settled.';
COMMENT ON FUNCTION public.notify_ticket_reply() IS
  'Trigger fn: inserts notifications row when a non-investor (staff) reply lands on a ticket.';
COMMENT ON FUNCTION public.notify_bank_change_status_change() IS
  'Trigger fn: inserts notifications row when bank_change_request flips pending→approved|rejected.';
