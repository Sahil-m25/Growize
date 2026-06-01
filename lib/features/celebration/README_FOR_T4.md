# Celebration — integration notes for T4

T1 built this feature in isolation. The trigger is **not** wired into
home_screen yet — that's T4's job. This file is the contract.

## Files in this folder

- `celebration_screen.dart` — the full-screen overlay.
- `celebration_flag.dart`   — Hive-backed `hasSeen` / `markSeen`.
- `celebration_trigger.dart` — gating + push logic.
- `preview_entry.dart`      — QA ListTile that re-opens the overlay.

Route registered: `/celebration?amount=…&project=…&date=…`
(see `lib/core/navigation/router.dart`).

## How to wire into home_screen

Inside `HomeScreen`'s state, after the first frame:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ref is from the ConsumerStatefulWidget — keep it the same instance.
    CelebrationTrigger.maybeShow(context, ref);
  });
}
```

Imports you'll need:

```dart
import 'package:arl_app/features/celebration/celebration_trigger.dart';
```

That's it. The trigger handles:

1. Reading `CelebrationFlag.hasSeen()` (no-op if already seen).
2. Awaiting `payoutsProvider` and bailing if the list is empty.
3. Pushing `/celebration` with the first payout's amount / project / date.
4. Persisting `markSeen` after the screen pops.

## How to add the preview tile

In Profile → Settings (or a debug menu), drop in:

```dart
import 'package:arl_app/features/celebration/preview_entry.dart';

// inside a ListView / Column of settings rows:
const CelebrationPreviewEntry(),
```

The preview pushes `/celebration` directly with sample data (₹41,000 ·
EKA · Mar 15, 2026) and does **not** modify the seen flag, so QA can
re-trigger it without wiping Hive. If QA needs to reset the real flag
to test the auto-trigger flow, call `CelebrationFlag.reset()` from a
debug menu.

## What T1 deliberately did NOT do

- Did not call `CelebrationTrigger.maybeShow` from anywhere — T4 does this.
- Did not change any feature folder other than `financials` and `celebration`.
- Did not touch `route_names.dart` — the `/celebration` literal is
  contained inside `router.dart` + `preview_entry.dart` + `celebration_trigger.dart`. If you'd like a `RouteNames.celebration` constant, add
  it in T4's pass when you also add the home-screen call site.
- Did not add packages to `pubspec.yaml`. Hive (already a dep) backs the
  seen flag in a dedicated box (`celebration_cache`) that opens lazily.

## Tested via

`dart analyze lib/features/financials lib/features/celebration lib/core/navigation/router.dart` — zero errors.
