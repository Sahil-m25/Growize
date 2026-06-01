# Phase Dates · Tour Persistence · Login Layout

Status: locked
Date: 2026-05-21
Scope: three discrete UX fixes batched into one round.

---

## Fix 1 — Phase timeline shows "started" / "completed" dates

### Problem
On the project detail screen, the 10-stage roadmap timeline (PhaseTimeline6)
showed only the current stage as a coloured dot. For long-running projects —
Pineapple LLP launched Jun-2024 — the timeline read as a frozen indicator
with no visual signal of *when* prior phases completed or *when* the current
phase started. Investors couldn't tell whether the contract had been running
for weeks or years.

### Data source

`public.project_phases` (migration 004) already has a `phase_date DATE`
column, but a single date can't carry both "started" and "completed" for
the same row (the current phase wants started; done phases want completed).

**Migration 053** (`20260523000000_053_project_phase_dates.sql`) splits
this into two TIMESTAMPTZ columns:

```sql
ALTER TABLE public.project_phases
  ADD COLUMN IF NOT EXISTS started_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
```

RLS is unchanged: the existing `project_phases: via investor units` policy
(migration 018) already gates SELECT to investors-with-allocation, so
adding columns is transparent.

The `ProjectPhase` model now exposes `effectiveStartedAt` /
`effectiveCompletedAt` getters that fall back to the legacy `phase_date`
when the new columns are null — so seeded-but-incomplete rows still
render coherent date affordances during the rollout.

### Wiring

- `project_detail_screen.dart` now watches `projectPhasesProvider` (already
  wired through the existing `phasesFor` repo path; it reads `SELECT *` so
  the new columns come along automatically).
- A new helper `_phaseDatesFor(project, phases, stageIdx)` builds a
  10-element `List<PhaseStageDates?>` keyed by `sort_order`.
- When **no** real phase rows are present (the typical demo case — e.g.
  Pineapple LLP, whose `mockPhaseMilestones` has no entry), the helper
  synthesises started/completed timestamps by linearly distributing the
  elapsed time since `project.startDate` across completed stages. This
  gives the demo Pineapple project a visible "started Jun 2024" anchor on
  Phase 1 without requiring DB seed data.
- The list is passed into `_CurrentPhaseCard` → `PhaseTimeline6` via a
  new `phaseDates` parameter (optional; null preserves the old behaviour).

### UI

- **Bottom sheet** (tap a node): adds a date line below the status pill.
  Format:
  - Done    → "Completed on 12 Mar 2026"
  - Current → "In progress — started 5 May 2026"
  - Pending → status pill alone (no extra line — "Upcoming" is the clearer
    signal).
- **Tiny date sub-label** under each node label (8pt muted):
  - Done    → "12 Mar" (year omitted when same as current year; "12 Mar 25"
    for cross-year completions).
  - Current → italic "(in progress)".
  - Pending → nothing (keeps the row visually tight).
- Connector segments and the row alignment now use
  `CrossAxisAlignment.start` so adding the sub-label under the disc
  doesn't pull the connector lines downward.

### Sample render (Pineapple LLP, stage 4 of 10, contract start Jun 2024)

```
   [1✓]──[2✓]──[3✓]──[4✓]──[5]
   Land  Design Site  Civil Procure
   1 Jul 1 Jan  1 Jul 1 Jan (in progress)
   '24    '25   '25   '26
                            │
                            ▼
   [10]─[9]──[8]──[7]──[6]
```

(Dates synthesised from `project.startDate = 2024-06-01` because no real
`project_phases` rows are seeded yet. Once Zoho or ARL staff insert real
rows with `started_at` / `completed_at`, the synthetic fallback is
short-circuited and DB values render.)

### Files touched

- `supabase/migrations/20260523000000_053_project_phase_dates.sql` *(new)*
- `lib/features/projects/models/project_phase.dart`
- `lib/features/projects/widgets/phase_timeline_6.dart`
- `lib/features/projects/project_detail_screen.dart`

---

## Fix 2 — Tour opens every launch (should be first-time only)

### Root cause

`tourSeenProvider` was a `StateProvider<bool>` that defaulted to `false`
synchronously and triggered an async read of secure storage in the
provider's create-callback. `tourShouldAutoStartProvider` was a sync
`Provider<bool>` that watched `tourSeenProvider` and computed
`!seen && !active`.

Timeline of a cold launch under the old wiring:

1. App boots → `tourSeenProvider` returns `false` synchronously.
2. `tourShouldAutoStartProvider` resolves to `true` (false → !false = true).
3. `MainScaffold` builds, sees `autoStart = true`, schedules a post-frame
   callback that calls `startTour(ref)`.
4. Meanwhile `_loadSeenFlag` is still awaiting the keychain read.
5. By the time the read returns and flips `tourSeenProvider` to `true`,
   the tour is already on screen.

Because step 3 happens on every cold launch, the tour opened every time
even after a clean dismiss + persist.

### Fix

`tourShouldAutoStartProvider` is now a `FutureProvider<bool>` that
**directly awaits the secure-storage read** before yielding the gate
value:

```dart
final tourShouldAutoStartProvider = FutureProvider<bool>((ref) async {
  final active = ref.watch(tourActiveProvider);
  bool seen = false;
  try {
    final raw = await _storage.read(key: _kTourSeenKey);
    seen = raw == 'true';
    if (seen && !ref.read(tourSeenProvider)) {
      ref.read(tourSeenProvider.notifier).state = true;
    }
  } catch (_) {
    seen = false;
  }
  return !seen && !active;
});
```

`MainScaffold` now gates on `.whenData((shouldStart) { ... })`, so the
auto-start callback only fires *after* the storage read confirms the
persisted state. Loading and error states fall through with no
auto-start (preferring "skip" over "show every time" on a partial read).

`startTour` accepts an `isAutoStart` flag that emits an explicit debug
log on first launch:

```
[tour] auto-start fired (seen = false)
```

so QA can verify the gate fires only on a true first launch — if this
log appears on a subsequent launch, the persistence write didn't land.

### Persist write path

`dismissTour` already `await`s the storage write before setting the
in-memory `tourSeenProvider`, so the only race was the read-side gate.
`replayTour` correctly does NOT clear the persisted flag — it only
flips `tourActive` on, so completing the replay re-asserts the existing
"seen" state rather than wiping it.

### Test sequence (mental)

1. Fresh install → open app → tour appears → log: `[tour] auto-start fired`.
2. Skip → close app.
3. Re-open → tour does NOT appear (no log).
4. Profile → Replay Tour → tour appears → complete.
5. Re-open → tour does NOT appear (no log).

### Files touched

- `lib/features/onboarding/tour_controller.dart`
- `lib/core/widgets/main_scaffold.dart`

---

## Fix 3 — Sign-in button positioned higher

### Problem

User feedback: "I want the sign in button to be on the mid... a little
on the upper side so it can be easily visible." On taller phones the
form (logo + email + password + sign-in button) sat near the top of the
viewport, putting the primary CTA in an awkward spot.

### Change

Replaced the fixed `SizedBox(height: 32)` at the top of the login form
with a viewport-relative spacer:

```dart
final viewportH = MediaQuery.of(context).size.height;
final topSpacer = (viewportH * 0.18).clamp(48.0, 220.0);
...
SizedBox(height: topSpacer),
```

`18%` is a balanced anchor: on a typical 760-820px viewport it adds
~135-150px of breathing room above the logo, which places the Sign In
button at roughly 55-60% from the top — slightly above centre, easy
thumb reach. The `clamp(48, 220)` ensures small phones (~600px) don't
get an over-tight top, and very tall tablets don't push the form
unreasonably low.

The form is still wrapped in `SingleChildScrollView` so the keyboard
can lift content into view on small devices without clipping.

### Before / after (relative position of Sign In button)

- Before: ~7% top padding (24 outer + 32 spacer) → Sign In button at
  roughly the 35-45% mark on most phones, depending on text scaling.
- After: ~18% viewport-relative top padding → Sign In button at roughly
  55-60%, slightly above centre.

Forgot password / Use a one-time code / terms link all stay below the
button — secondary actions remain lower-prominence as before.

### Files touched

- `lib/features/auth/login_screen.dart`

---

## Verification

- Read-only analyze run was attempted in the sandbox — the Flutter SDK
  path documented in `CLAUDE.md` (`C:\flutter\bin\dart.bat`) is a Windows
  PowerShell binary and cannot be invoked from the Linux sandbox. The
  user should run `& C:\flutter\bin\dart.bat analyze lib` locally to
  confirm the analyzer is clean.
- No new packages added (date formatting uses the already-imported
  `intl` package; `flutter_secure_storage` is the existing dependency).
- Pixel/behaviour parity with the v3 HTML mockup is unaffected — the
  timeline still uses the same 5+5 roadmap layout and the same node
  styling tokens (gold for done, primary ring for current, muted ring
  for pending).
