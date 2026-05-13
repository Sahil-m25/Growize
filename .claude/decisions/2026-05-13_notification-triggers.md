# Decision — Notification triggers (KYC / exit / ticket-reply / bank-change)

**Date:** 2026-05-13
**Status:** locked
**Scope:** FG-06 (selective) from e2e_test_plan_v2_extended_2026-05-13.md

## Problem
Four investor-visible state transitions today don't produce an
in-app notification:
1. KYC verdict (pending → verified | rejected).
2. Exit-request resolution (pending → approved | rejected | settled).
3. Staff reply on a support ticket.
4. Bank-change verdict (pending → approved | rejected).

Each lives in a different write path — some via Edge Function,
some via ops directly in Supabase Studio, some via the
zoho-crm-webhook. Layering "also write to notifications" into
every caller is fragile (easy to miss, easy to drift). Atomic
co-write with the state change is the only path that's
guaranteed to fire.

## Decision
DB-level triggers (`AFTER UPDATE` / `AFTER INSERT`) that detect
the relevant transition and `INSERT INTO notifications`. Functions
run `SECURITY DEFINER` with `SET search_path = public, pg_temp`
so they can write notifications regardless of the calling role
(authenticated investor, service_role, ops Studio user) and
without being trickable by a temp-schema function shadow.

## What changed

### Schema (migration 034)
- Expanded `notifications.type` CHECK constraint to add
  `kyc`, `exit`, `bank_change` (existing values preserved).
  `ticket` already existed and is reused for staff replies.
- Four trigger functions, one trigger per source table.

### Trigger details

| Source                  | Event                              | Type fired   | Investor lookup                    |
|-------------------------|------------------------------------|--------------|------------------------------------|
| `investors`             | UPDATE `kyc_status` pending→verified/rejected | `kyc`        | `NEW.id` (PK = auth.users.id)      |
| `exit_requests`         | UPDATE `status` pending→approved/rejected/settled | `exit`       | `NEW.user_id`                      |
| `ticket_messages`       | INSERT WHERE `sender_type != 'investor'`     | `ticket`     | Join `support_tickets.investor_id` |
| `bank_change_requests`  | UPDATE `status` pending→approved/rejected      | `bank_change`| `NEW.investor_id`                  |

- Every trigger uses `IS DISTINCT FROM OLD.<col>` to avoid
  firing on no-op writes that touch the row without actually
  changing the field.
- Ticket-reply trigger silently no-ops when the referenced
  ticket is missing — covers the (very narrow) race where a
  ticket is deleted between the message INSERT and the trigger
  firing.
- Metadata JSONB carries IDs (`kyc_status`, `exit_request_id`,
  `ticket_id`, `message_id`, `bank_change_request_id`, etc.)
  so the Flutter notification deep-link can route correctly.

### Hardening
- Each function has `EXECUTE` revoked from PUBLIC. The trigger
  context retains its ability to call them; direct
  `SELECT notify_xxx(...)` from PostgREST does not.
- `SET search_path = public, pg_temp` prevents the
  CVE-style attack where a temp-schema function shadows
  `notifications` and intercepts the insert.

## Trade-offs
- DB triggers add a small write-time tax (~one extra row insert).
  Acceptable given the alternative (every caller remembers to
  also notify) is strictly worse for reliability.
- Type CHECK expansion is an additive change — existing rows
  remain valid, no backfill needed.
- The ticket-reply trigger doesn't deduplicate against multiple
  rapid staff replies; each insert produces a notification.
  Future enhancement could collapse "3 replies in 10 minutes"
  into one bell-icon ping at the Flutter layer.

## Open questions
- The `kyc_status` CHECK constraint on `investors` allows
  `pending`, `verified`, `rejected` but the webhook's
  `mapKycStatus` also references an `in_progress` value as
  "canonical". If the CHECK is later expanded to include
  `in_progress`, the trigger predicate
  `OLD.kyc_status = 'pending'` will miss the
  `in_progress → verified` transition. Revisit when the
  webhook's `in_progress` path lands.

## Files
- supabase/migrations/20260513040000_034_notification_triggers.sql
