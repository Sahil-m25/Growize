# 2026-05-21 — Phase roadmap, Monthly Updates, Explore tile redesign

Status: locked

Three UI fixes shipped in one pass against the Project Detail and Explore screens.

## Fix 1 — Phase timeline 5+5 roadmap

`lib/features/projects/widgets/phase_timeline_6.dart`

The 10-stage timeline used to render as a single horizontally-scrollable strip with 22 px nodes — visually it read like a thin progress bar and was easy to miss on phones. Reshaped into a two-row "snake" roadmap:

```
[1]--[2]--[3]--[4]--[5]
                      |
                      v
[10]-[9]--[8]--[7]--[6]
```

Node colours per spec: done = filled gold, current = outlined primary (with a 2.5 px ring and a soft accent halo), pending = outlined muted. Node diameter is `LayoutBuilder`-clamped between 36 and 48 px depending on width, so the layout reads big on 360 px phones and stays compact on tablet/web.

Tap on any node opens a bottom sheet with the full stage label (e.g. "Compliance Closed + Go-live") plus a status pill (Completed / In progress / Upcoming) and the "Stage N of 10" caption. Per the user's instruction, we kept the data binding the same — the widget still receives only `currentStageIndex`, so the bottom sheet shows status derived from the index rather than a real `completed_at` date (none is plumbed yet).

Public API is unchanged: `PhaseTimeline6({required int currentStageIndex, Color? accentOverride})`, plus `labelAt(int)` and `stageCount` statics. All existing call sites in `project_detail_screen.dart` continue to work without changes.

## Fix 2 — Monthly Updates: dynamic data

The Monthly Updates section was previously bound to `project_phases` (the milestone/checklist model) and rendered as an accordion of phases. Per the user, this isn't really "monthly updates" — it's a milestone tracker, and most projects don't have phase rows seeded so the section often looked empty or static.

New data model — Supabase migration `052_project_updates`:

```sql
CREATE TABLE public.project_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  update_date date NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  image_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX project_updates_project_date_idx
  ON public.project_updates(project_id, update_date DESC);
```

RLS mirrors the `project_phases: via investor units` policy — investors can SELECT a row only when they hold a non-soft-deleted `investor_units` row against the same `project_id`. Staff write via service_role.

Seeded 4 demo rows against Samsung LLP (`46c226a0-3969-496d-8cee-f6661ff0ad96`) for testing.

Flutter wiring:

- New model `ProjectUpdate` (`lib/features/projects/models/project_update.dart`).
- `ProjectsRepository.updatesFor(projectId)` — Hive-cached, network-first, six-row limit, ordered `update_date DESC`. Demo project ids short-circuit to an empty list.
- Riverpod family `projectUpdatesProvider(projectId)` in `projects_provider.dart` — watches `authStateProvider` so the result re-fetches on session attach.
- `_MonthlyUpdatesCard` in `project_detail_screen.dart` rewritten to consume the new provider. Cards render: gold date pill → bold charcoal title → muted body → optional cover image. Loading state shows three skeleton bars; error and empty states show a single muted inline message ("No updates yet. Check back soon.").
- Removed the now-unused `_phaseStatusColor` / `_phaseStatusLabel` helpers and the `_expandedPhases` accordion state, plus the `ProjectPhase` import.

## Fix 3 — Explore tile redesign

`lib/features/explore/widgets/project_tile.dart` and `lib/features/explore/explore_detail_screen.dart`.

Old tile body had: crop chip -> fill bar -> "X / Y units · N available" caption -> price per unit. The user asked for a clearer split between total inventory, area, and remaining-units progress.

New tile body:

1. Project name + location (unchanged).
2. Crop chip (unchanged).
3. Two compact stat pills side-by-side: `120 units total` · `5.2 acres`. Each pill has a small icon and falls back to `—` when the underlying field is null.
4. A "Remaining" strip: `X of Y remaining` left-aligned, `Z% sold` right-aligned, with a 5 px sand-on-accent progress bar underneath whose filled portion = sold units.
5. Price per unit, with a forward arrow added on the right side as the "tap to learn more" CTA hint.

Sold-out and coming-soon listings still get their existing dedicated pill in place of the remaining-units strip — those visual treatments were validated by previous UX rounds and worth keeping.

`explore_detail_screen.dart` — replaced the single "UNITS AVAILABLE" stat card (with its inline fill bar) with two side-by-side cards: `TOTAL UNITS` and `AREA`. Below the existing Price + Expected Return row a new `SUBSCRIPTION PROGRESS` card shows the same remaining-units headline + horizontal bar. Removed the now-unused `fill_bar.dart` import.

## Implementation notes

- No new packages added (`pubspec.yaml` untouched).
- `marketplace_project.dart` already exposed `acreageAcres` — no model changes needed.
- RLS uses `(SELECT auth.uid())` not `auth.uid()` directly (matches Postgres planner-cache best-practice already in use across other tables).
- Hive cache key for updates is `updates_<projectId>` (versioned via the `_kUpdates` constant on the repo).

## Verification

- `dart analyze lib` could not be run from this session (Linux sandbox has no Dart toolchain). Manual diff review: all imports are accounted for, no dangling references to removed identifiers, public APIs of `PhaseTimeline6` and `ProjectTile` preserved for callers.
- Migration applied successfully (`052_project_updates`) and 4 seed rows confirmed against Samsung LLP.
- Run `& C:\flutter\bin\dart.bat analyze lib` from the Windows host to confirm no regressions before merge.
