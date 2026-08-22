# Eka stage update — SHIPPED

> ## Production state (2026-08-22, end of day)
>
> Database: `oynfhdqizebvgmaoiuax` "Growize Main DB".
>
> | | |
> |---|---|
> | Migrations applied | 066, 067, 068, 069 |
> | Eka stage 0 "Land Closed" | **done** |
> | Stages 1–9 | pending (timeline reads 2/10) |
> | Notifications sent | **3 investors** — Kandarp, Jaideep, Sahil |
> | Still unread | 3 (no push transport; delivery is on app open) |
> | `phase_copy` rows | 10 |
> | Milestone photos attached | 0 — no images uploaded yet |
> | Sahil test allocation | present (`TEST-SAHIL-EKA-20260822`) |
> | Eka units_issued | 2 — unchanged by the test row |
>
> What investors currently see:
>
> > **Land Acquired!**
> > EKA LLP: we will start construction next. We'll keep you posted.
>
> Wording lives in `project_phases.custom_title` / `custom_body` for
> Eka's stage 0, so it can be changed with one UPDATE and no migration.
>
> **The Flutter changes in this commit are NOT yet deployed.** Until a
> build ships, users on the current APK get the notification (server-side)
> but still see the old calendar-derived timeline.

## The question that started this

"Is the notification thing enabled?" Answer: partly.

| Layer | State | Verified how |
|---|---|---|
| In-app feed (bell + Activity) | working — live types in prod today are `kyc` and `document` | `select distinct type from notifications` |
| Stage / phase notifications | **did not exist** — the only trigger on `project_phases` is `trg_project_phases_updated_at`, and the table has **0 rows** | `pg_trigger` on `project_phases` |
| Stage shown on the timeline | was calendar math (`monthsElapsed / totalMonths`) | `_stageIndexFor` in `project_detail_screen.dart` |
| Native push | **not built** — no `device_tokens` table, `fcm_service.dart` is a stub | `to_regclass('public.device_tokens')` → null |

## What prod actually looks like (and where the repo lies)

The repo's `supabase/migrations/` is **not** the source of truth for this
database. Verified drift:

| Repo says | Prod actually |
|---|---|
| `notifications_type_check` = the 8 types from migration 034 | already widened to 11, **including `phase_update`, `document`, `new_project`** |
| `documents-sync` inserts are silently rejected | **not true in prod** — `document` notifications are live and present |
| `projects.zoho_llp_id` | **no such column.** Zoho id is on `llps.zoho_llp_id`; `projects.llp_id` → `llps.id` |
| `project_phases.started_at` / `.completed_at` (migration 053) | **absent** — 053 never reached this database |
| migrations 062 / 064 / 065 applied | not in prod's migration list; prod instead has 13 migrations applied directly after `061` (portfolio_summary fixes, ROI, admin enablement) that exist in no repo file |
| — | `investor_units` and `projects` carry `deleted_at` soft-delete columns that no sync function filters on |

Consequence for this work: **applying migration 066 releases no document
backlog.** That warning from the first pass is withdrawn — prod already
had the constraint. Section 0 of the migration is a no-op there; it is
kept so the file stands alone in any environment still on 034.

## Eka, concretely

| | |
|---|---|
| `projects.id` | `6cb9fe7c-b173-4e39-a613-93bda03ca9f4` |
| `llps.zoho_llp_id` | `1169101000001929260` |
| status | Open for Reservation · 22 units · 2 issued · launched 2026-06-12 |
| `investor_units` | 2 rows, 2 distinct investors, `allocation_status` "Issued", none soft-deleted |
| `user_settings` | **0 rows org-wide** — nobody has opted out, so all 2 get notified |
| `project_phases` | 0 rows — stages must be seeded |
| **Blast radius** | **2 investors** |

RLS checked: `project_phases: via investor units` lets both holders read
the seeded rows, and `notifications: read own rows` lets them read the
notification. Nothing extra needed.

## Files

| File | What it is |
|---|---|
| `supabase/migrations/20260822000000_066_phase_update_notifications.sql` | the trigger, fan-out, dedupe index; skips soft-deleted allocations and projects |
| `supabase/tests/066_phase_update_notifications_test.sql` | fixture mirroring the **real** prod schema |
| `supabase/tests/066_assertions.sql` | 18 assertions — green on PostgreSQL 16.13 |
| `scripts/eka_stage_update.sql` | 5-step seed/advance, joins through `llps`, uses `phase_date` not `started_at` |
| `lib/features/projects/project_detail_screen.dart` | `_stageIndexFor` reads phase rows |
| `lib/features/activity/models/notification.dart`, `activity_screen.dart` | render `phase_update` |
| `docs/plans/2026-08-22_push_notifications_fcm_scope.md` | the push follow-up |

Verification: `dart analyze lib` output is byte-identical before and
after the Dart changes (284 pre-existing infos, 0 new, 0 errors). The
migration was applied to a scratch Postgres built from the verified prod
schema; all 18 assertions pass, including that soft-deleted allocations
and soft-deleted projects are skipped and that the trigger never touches
the missing 053 columns.

## Order of operations

1. **Apply migration 066.** No-op on the constraint, adds the function,
   trigger and index.
2. **Set `\set target_stage`** in `scripts/eka_stage_update.sql`.
3. **Steps 1–3** — read only. Step 3 prints the 2 investors.
4. **Step 4** — seeds the 10 stage rows, notifies nobody. Inspect, commit.
5. **Step 5** — the step that reaches users.
6. **Ship the Flutter build** so the timeline agrees with the notification.
   Until then, users on the old APK get the notification but the timeline
   still moves on calendar time.

## Open items

- **Which database is production?** The org has a second project,
  "ARL Investor DB" (`osdqjdmsqpexoiqjidfe`), created 2026-06-29 with
  **14 investors** and a completely different schema — `holdings`,
  `transactions`, `updates`, `profiles`, `managers`, `tickets`,
  `user_preferences`. The repo (`config.toml`, `.env.example`) points at
  Growize Main DB, which has only 4 investors. Worth confirming before
  anyone assumes Growize Main DB is where users live.
- **Migration 053** (`started_at` / `completed_at` on `project_phases`)
  was never applied. Nothing here needs it — the app falls back to
  `phase_date` — but applying it would give the timeline richer
  "Completed 12 Mar" / "In progress — started 5 May" date lines.
- **Soft-delete leak in the sync functions.** `gallery-sync` and
  `documents-sync` fan out over `investor_units` without filtering
  `deleted_at`, so withdrawn investors still get photo and document
  notifications. Migration 066's trigger does filter it. Not fixed here.
- **No Zoho sync for phases.** The EKA LLP record has no
  `Phase_1..Phase_10` fields and no handler reads them.
- **Delivery is on-open.** No push, no realtime subscription on
  `notifications`.
