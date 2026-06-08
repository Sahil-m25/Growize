-- ============================================================
-- MIGRATION 048 — Three notification-trigger refinements.
--
-- (A) DEF-2026-05-15-11 (DEF-OPS-5): kyc_resubmissions status
--     changes do NOT fire a notification. Investor learns only
--     when ops separately flips investors.kyc_status. Add a
--     trigger on kyc_resubmissions that emits a 'kyc'
--     notification on accept/reject transitions.
--
-- (B) DEF-2026-05-15-13 (D-4): notify_ticket_reply hard-codes
--     "New reply on your ticket" wording. For ops-initiated
--     tickets (Recipe T-6) the first staff message is NOT a
--     reply. Branch the title/body on whether prior
--     ticket_messages exist for this ticket.
--
-- (C) DEF-2026-05-15-18 (DEF-OPS-7): document by-design choice
--     that kyc_status transitions INTO 'in_progress' do not
--     emit a notification. Only terminal states (verified,
--     rejected) notify. Attach a COMMENT so future readers
--     don't mistake it for a missing trigger branch.
-- ============================================================

-- (A) kyc_resubmissions notification trigger -----------------
-- Guarded with IF EXISTS so the migration is a no-op if the
-- table never landed in this environment.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name   = 'kyc_resubmissions'
  ) THEN
    -- Function ---------------------------------------------------
    CREATE OR REPLACE FUNCTION public.notify_kyc_resubmission_status_change()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fn$
    DECLARE v_title TEXT; v_body TEXT;
    BEGIN
      -- Fire on any transition into accepted / rejected. Mirrors
      -- the investors.kyc_status terminal-state semantics so the
      -- investor sees a single bell event for the lifecycle stage.
      IF NEW.status IN ('accepted', 'rejected')
         AND NEW.status IS DISTINCT FROM OLD.status THEN
        CASE NEW.status
          WHEN 'accepted' THEN
            v_title := 'KYC re-submission accepted';
            v_body  := 'Your KYC re-submission has been accepted.';
          ELSE
            v_title := 'KYC re-submission rejected';
            v_body  := 'Your KYC re-submission has been rejected. Please review and re-submit.';
        END CASE;
        INSERT INTO public.notifications (investor_id, type, title, body, metadata)
        VALUES (
          NEW.investor_id, 'kyc', v_title, v_body,
          jsonb_build_object(
            'kyc_resubmission_id', NEW.id,
            'status', NEW.status,
            'previous_status', OLD.status
          )
        );
      END IF;
      RETURN NEW;
    END;
    $fn$;

    COMMENT ON FUNCTION public.notify_kyc_resubmission_status_change() IS
      'Trigger fn: inserts notifications row when kyc_resubmissions '
      'status flips to accepted|rejected. Pairs with the existing '
      'notify_investor_kyc_status_change so the investor learns '
      'about the re-submission outcome even if ops does not flip '
      'investors.kyc_status in the same transaction.';

    -- Trigger binding -------------------------------------------
    DROP TRIGGER IF EXISTS trg_notify_kyc_resubmission_status_change
      ON public.kyc_resubmissions;
    CREATE TRIGGER trg_notify_kyc_resubmission_status_change
      AFTER UPDATE OF status ON public.kyc_resubmissions
      FOR EACH ROW
      EXECUTE FUNCTION public.notify_kyc_resubmission_status_change();
  ELSE
    RAISE NOTICE 'public.kyc_resubmissions not present — skipping (A).';
  END IF;
END;
$$;

-- (B) notify_ticket_reply: branch on first-message ------------
CREATE OR REPLACE FUNCTION public.notify_ticket_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_investor_id   UUID;
  v_short_id      TEXT;
  v_is_first      BOOLEAN;
  v_title         TEXT;
  v_body          TEXT;
BEGIN
  -- Investor self-replies do not notify the investor.
  IF NEW.sender_type = 'investor' THEN
    RETURN NEW;
  END IF;

  SELECT investor_id INTO v_investor_id
    FROM public.support_tickets
   WHERE id = NEW.ticket_id;
  IF v_investor_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_short_id := substr(NEW.ticket_id::text, 1, 8);

  -- v_is_first: this is the FIRST message on the ticket
  -- (i.e. no prior ticket_messages row exists besides NEW).
  -- Branch the title/body so ops-initiated tickets get
  -- "New message from ARL" instead of the misleading "New reply".
  SELECT NOT EXISTS (
    SELECT 1 FROM public.ticket_messages
     WHERE ticket_id = NEW.ticket_id
       AND id <> NEW.id
  ) INTO v_is_first;

  IF v_is_first THEN
    v_title := 'New message from ARL';
    v_body  := 'A new ticket #' || v_short_id || ' has been opened by ARL support.';
  ELSE
    v_title := 'New reply on your ticket';
    v_body  := 'New reply on ticket #' || v_short_id || '.';
  END IF;

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  VALUES (
    v_investor_id, 'ticket', v_title, v_body,
    jsonb_build_object(
      'ticket_id',   NEW.ticket_id,
      'message_id',  NEW.id,
      'sender_type', NEW.sender_type,
      'is_first',    v_is_first
    )
  );
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_ticket_reply() IS
  'Trigger fn: inserts notifications row when a staff message lands on '
  'a ticket. Branches on whether the message is the first on the '
  'ticket so ops-initiated tickets (Recipe T-6) are titled '
  '"New message from ARL" instead of "New reply on your ticket".';

-- (C) Document the by-design KYC in_progress silence ----------
COMMENT ON FUNCTION public.notify_investor_kyc_status_change() IS
  'Trigger fn: inserts notifications row when investor KYC flips '
  'pending -> verified|rejected. BY DESIGN: transitions INTO '
  '''in_progress'' do NOT fire a notification. Only terminal '
  'states do — the in_progress hop is an internal ops state and '
  'too chatty to surface to investors. See DEF-2026-05-15-18.';

-- Rollback:
--   (A) DROP TRIGGER trg_notify_kyc_resubmission_status_change ON public.kyc_resubmissions;
--       DROP FUNCTION public.notify_kyc_resubmission_status_change();
--   (B) Restore prior notify_ticket_reply() body from migration 034.
--   (C) Restore the prior COMMENT (one-line) from migration 034.
