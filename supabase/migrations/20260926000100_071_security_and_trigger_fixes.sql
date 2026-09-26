-- =====================================================================
-- 071 — Security + trigger fixes found in the 2026-09-26 live-schema audit
-- =====================================================================
-- NOT YET APPLIED to production. Review, then run in the SQL editor (or
-- `supabase db push`). Verified on a Postgres 16 replica of 070:
--   * stage advance succeeds and notifies the project's investors
--   * each investor sees only their own portfolio_summary row
--   * anon/authenticated can no longer call upsert_phase_project_update
--   * get_portfolio_summary(), is_admin(), uid() still callable
-- =====================================================================

begin;

-- 1) Stage notifications were broken: the trigger read NEW.is_demo, a column
--    project_phases does not have, so every UPDATE to status 'current' or
--    'done' raised "record new has no field is_demo" and was rolled back.
--    Demo data is filtered elsewhere (payouts.is_demo); phases have no flag.
CREATE OR REPLACE FUNCTION public.notify_project_phase_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kind TEXT; v_project_name TEXT;
  v_title TEXT; v_body TEXT; v_meta JSONB; v_notified INT;
BEGIN
  IF NEW.status = 'current'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'current') THEN
    v_kind := 'started';
  ELSIF NEW.status = 'done' AND TG_OP = 'UPDATE'
        AND OLD.status IS DISTINCT FROM 'done' THEN
    v_kind := 'completed';   -- BACKFILL GUARD: UPDATE only, never INSERT
  ELSE
    RETURN NEW;
  END IF;

  SELECT p.name INTO v_project_name FROM public.projects p
  WHERE p.id = NEW.project_id AND p.deleted_at IS NULL;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT r.title, r.body INTO v_title, v_body
    FROM public.resolve_phase_copy(NEW::public.project_phases, v_kind, v_project_name) r;

  v_meta := jsonb_build_object(
    'project_id', NEW.project_id, 'project_name', v_project_name,
    'stage_index', NEW.sort_order, 'phase_name', NEW.phase_name,
    'kind', v_kind,
    'cta_route', '/projects/' || NEW.project_id::TEXT,
    'cta_label', 'View Project');

  IF NEW.image_url IS NOT NULL AND TRIM(NEW.image_url) <> '' THEN
    v_meta := v_meta || jsonb_build_object('image_url', NEW.image_url);
  END IF;

  INSERT INTO public.notifications (investor_id, type, title, body, metadata)
  SELECT DISTINCT iu.investor_id, 'phase_update', v_title, v_body, v_meta
  FROM public.investor_units iu
  LEFT JOIN public.user_settings us ON us.user_id = iu.investor_id
  WHERE iu.project_id = NEW.project_id
    AND iu.deleted_at IS NULL
    AND COALESCE(us.notifications_enabled, TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.investor_id = iu.investor_id AND n.type = 'phase_update'
        AND n.metadata ->> 'project_id'  = NEW.project_id::TEXT
        AND n.metadata ->> 'stage_index' = NEW.sort_order::TEXT
        AND n.metadata ->> 'kind'        = v_kind);
  GET DIAGNOSTICS v_notified = ROW_COUNT;

  PERFORM public.upsert_phase_project_update(
            NEW::public.project_phases, v_kind, v_title, v_body);

  RAISE LOG 'notify_project_phase_change: project=% stage=% kind=% notified=%',
            NEW.project_id, NEW.sort_order, v_kind, v_notified;
  RETURN NEW;
END $function$;

-- 2) portfolio_summary bypassed RLS (no security_invoker, owned by postgres),
--    so any signed-in investor could read every investor's invested amount
--    and payouts. The app uses get_portfolio_summary() instead; keep the view
--    but make it obey RLS and read-only.
alter view public.portfolio_summary set (security_invoker = on);
revoke all on public.portfolio_summary from anon, authenticated;
grant select on public.portfolio_summary to authenticated;

-- 3) SECURITY DEFINER helpers were executable by anon/authenticated through
--    PostgREST /rpc. upsert_phase_project_update lets the caller write
--    investor-facing project updates for ANY project. These are internal to
--    triggers (trigger execution does not need the caller's EXECUTE grant).
revoke execute on function public.upsert_phase_project_update(project_phases, text, text, text) from public, anon, authenticated;
revoke execute on function public.resolve_phase_copy(project_phases, text, text) from public, anon, authenticated;
revoke execute on function public.sync_phase_notifications() from public, anon, authenticated;
revoke execute on function public.set_kyc_submitted_at() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

-- 4) Defence in depth: drop Supabase's default blanket grants where no RLS
--    policy lets that role in anyway, and TRUNCATE/TRIGGER/REFERENCES
--    everywhere (TRUNCATE ignores RLS).
revoke all on public.app_releases, public.auth_request_throttle, public.consents,
              public.erasure_requests, public.nominees, public.phase_copy,
              public.project_documents, public.project_updates, public.projects_public
  from anon;
do $$
declare t record;
begin
  for t in select c.relname from pg_class c
           where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v')
  loop
    execute format('revoke truncate, trigger, references on public.%I from anon, authenticated', t.relname);
  end loop;
end $$;

commit;

-- 5) OPTIONAL — live ticket updates. ticket_detail_screen subscribes to
--    realtime changes on these tables, but the publication is empty, so
--    replies only appear after a manual refresh. Realtime respects RLS.
-- alter publication supabase_realtime add table public.ticket_messages, public.support_tickets;
