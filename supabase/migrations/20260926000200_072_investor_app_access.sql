-- =====================================================================
-- 072 — App Access gate for investors (hold before welcome)
-- =====================================================================
-- New Zoho Contacts now land as app_access = 'hold': their data syncs,
-- their login exists but is suspended, and no email is sent. Switching
-- Zoho Contacts.App_Access to "Invite" moves them to 'invited' and sends
-- the Growize welcome email (zoho-crm-webhook v36). request-auth-email v11
-- refuses login codes while on hold.
--
-- Everyone already in the app is live today -> backfilled to 'invited'.
-- =====================================================================
begin;

alter table public.investors
  add column if not exists app_access text not null default 'hold',
  add column if not exists invited_at timestamp with time zone;

alter table public.investors drop constraint if exists investors_app_access_check;
alter table public.investors
  add constraint investors_app_access_check check (app_access in ('hold', 'invited'));

update public.investors
   set app_access = 'invited',
       invited_at = coalesce(invited_at, onboarded_at, now());

-- Investors may update their own row (profile edits in the app) but must
-- never be able to change their own access state.
create or replace function public.guard_investor_app_access()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  if (new.app_access is distinct from old.app_access
      or new.invited_at is distinct from old.invited_at)
     and v_role in ('authenticated', 'anon') then
    raise exception 'app_access can only be changed by the Zoho sync';
  end if;
  return new;
end
$function$;

revoke execute on function public.guard_investor_app_access() from public, anon, authenticated;

drop trigger if exists trg_guard_investor_app_access on public.investors;
create trigger trg_guard_investor_app_access
  before update on public.investors
  for each row execute function public.guard_investor_app_access();

commit;
