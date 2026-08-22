\set ON_ERROR_STOP on
\pset pager off
CREATE OR REPLACE FUNCTION chk(label TEXT, got ANYELEMENT, want ANYELEMENT) RETURNS VOID
LANGUAGE plpgsql AS $$ BEGIN
  IF got IS NOT DISTINCT FROM want THEN RAISE NOTICE 'PASS  % (=%)', label, got;
  ELSE RAISE EXCEPTION 'FAIL  % : got % want %', label, got, want; END IF;
END; $$;

\echo '--- P1: constraint unchanged by re-applying 066 on an already-widened prod ---'
SELECT chk('P1 constraint set matches prod',
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
   WHERE conrelid='public.notifications'::regclass AND conname='notifications_type_check'),
  'CHECK ((type = ANY (ARRAY[''payout''::text, ''photo''::text, ''ticket''::text, ''reminder''::text, ''milestone''::text, ''kyc''::text, ''exit''::text, ''bank_change''::text, ''phase_update''::text, ''document''::text, ''new_project''::text])))'::TEXT);

\echo '--- T1: seeding done/pending notifies nobody ---'
INSERT INTO public.project_phases (project_id, phase_name, status, sort_order)
SELECT '6cb9fe7c-b173-4e39-a613-93bda03ca9f4', n.nm,
       CASE WHEN n.so < 1 THEN 'done' ELSE 'pending' END, n.so
FROM (VALUES (0,'Land Closed'),(1,'Design & Plan Locked'),(2,'Site Prep'),(3,'Core Civil'),
 (4,'Procurement Locked'),(5,'Water Source & Storage Ready'),(6,'Power Ready'),
 (7,'Greenhouse'),(8,'Production Systems Installed'),(9,'Compliance Closed + Go-live')) AS n(so,nm);
SELECT chk('T1 zero notifications', (SELECT COUNT(*)::INT FROM notifications), 0);

\echo '--- T2: advancing Eka to stage 1 hits exactly the right 2 investors ---'
UPDATE public.project_phases SET status='current', phase_date=CURRENT_DATE
WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=1;
SELECT chk('T2 total = 2 (prod blast radius)', (SELECT COUNT(*)::INT FROM notifications), 2);
SELECT chk('T2 Eka One notified',    (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000001'), 1);
SELECT chk('T2 Eka Two notified',    (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000002'), 1);
SELECT chk('T2 opted-out skipped',   (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000003'), 0);
SELECT chk('T2 SOFT-DELETED allocation skipped', (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000004'), 0);
SELECT chk('T2 other project skipped', (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000005'), 0);
SELECT chk('T2 title',    (SELECT DISTINCT title FROM notifications), 'Stage update: Design & Plan Locked'::TEXT);
SELECT chk('T2 body',     (SELECT DISTINCT body  FROM notifications), 'EKA LLP has moved to Design & Plan Locked.'::TEXT);
SELECT chk('T2 cta_route',(SELECT DISTINCT metadata->>'cta_route' FROM notifications), '/projects/6cb9fe7c-b173-4e39-a613-93bda03ca9f4'::TEXT);

\echo '--- T3: soft-DELETED PROJECT notifies nobody ---'
INSERT INTO public.project_phases (project_id, phase_name, status, sort_order)
VALUES ('33333333-3333-3333-3333-333333333333','Core Civil','current',3);
SELECT chk('T3 deleted-project investor skipped', (SELECT COUNT(*)::INT FROM notifications WHERE investor_id='aaaaaaaa-0000-0000-0000-000000000006'), 0);
SELECT chk('T3 total still 2', (SELECT COUNT(*)::INT FROM notifications), 2);

\echo '--- T4: idempotency / bounce ---'
UPDATE public.project_phases SET status='current' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=1;
UPDATE public.project_phases SET status='pending' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=1;
UPDATE public.project_phases SET status='current' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=1;
SELECT chk('T4 still 2 after replay+bounce', (SELECT COUNT(*)::INT FROM notifications), 2);

\echo '--- T5: a genuinely new stage notifies again ---'
UPDATE public.project_phases SET status='done' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=1;
UPDATE public.project_phases SET status='current' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=2;
SELECT chk('T5 now 4', (SELECT COUNT(*)::INT FROM notifications), 4);

\echo '--- T6: non-status edits stay silent ---'
UPDATE public.project_phases SET phase_name='Site Prep (rev)' WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=2;
UPDATE public.project_phases SET phase_date=CURRENT_DATE WHERE project_id='6cb9fe7c-b173-4e39-a613-93bda03ca9f4' AND sort_order=2;
SELECT chk('T6 still 4', (SELECT COUNT(*)::INT FROM notifications), 4);

\echo '--- T7: no reference to started_at/completed_at (migration 053 absent in prod) ---'
SELECT chk('T7 trigger ran without 053 columns', (SELECT COUNT(*)::INT FROM information_schema.columns
  WHERE table_name='project_phases' AND column_name IN ('started_at','completed_at')), 0);

\echo '--- T8: grants + index ---'
SELECT chk('T8 anon cannot execute', has_function_privilege('anon','public.notify_project_phase_change()','EXECUTE'), FALSE);
SELECT chk('T8 dedupe index exists', (SELECT COUNT(*)::INT FROM pg_indexes WHERE indexname='idx_notifications_phase_update_dedupe'), 1);

\echo ''
\echo '========== ALL PROD-ACCURATE TESTS PASSED =========='
