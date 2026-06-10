-- ============================================================
-- MIGRATION 060 — Lock down SECURITY DEFINER trigger/internal functions
--
-- These functions run as SECURITY DEFINER (elevated, RLS-bypassing) and
-- are only ever meant to fire as TRIGGERS or be called by service_role.
-- By Postgres default EXECUTE is granted to PUBLIC, and PostgREST exposes
-- every public-schema function as /rest/v1/rpc/<name> — so anon and
-- authenticated clients could invoke them directly. That is an
-- unnecessary privilege-escalation / abuse surface (Supabase security
-- advisors 0028/0029).
--
-- Revoking EXECUTE from PUBLIC/anon/authenticated removes them from the
-- callable API. Trigger execution does NOT check the caller's EXECUTE
-- grant, so all triggers keep working unchanged. service_role / owner
-- retain access. No functional impact.
--
-- Reversible: GRANT EXECUTE ON FUNCTION ... TO authenticated; (per fn)
-- ============================================================

revoke execute on function public.notify_bank_change_status_change()       from public, anon, authenticated;
revoke execute on function public.notify_consultation_request()            from public, anon, authenticated;
revoke execute on function public.notify_document_uploaded()               from public, anon, authenticated;
revoke execute on function public.notify_exit_request_status_change()      from public, anon, authenticated;
revoke execute on function public.notify_investor_kyc_status_change()      from public, anon, authenticated;
revoke execute on function public.notify_kyc_resubmission_status_change()  from public, anon, authenticated;
revoke execute on function public.notify_ticket_reply()                    from public, anon, authenticated;
revoke execute on function public.recompute_project_units(uuid)            from public, anon, authenticated;
revoke execute on function public.trg_recompute_project_units_fn()         from public, anon, authenticated;
revoke execute on function public.sync_investor_phone_to_auth()            from public, anon, authenticated;
