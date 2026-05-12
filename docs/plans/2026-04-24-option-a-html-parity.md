# Option A: HTML-Parity Fix (Logo + Back Buttons + Global Header)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring Flutter ARL app to visual + navigation parity with `Growize App Design.html`: restore top-left logo, global header on every shell screen, working back buttons, Inter font.

**Architecture:**
- Create `ArlAppBar` shared widget rendered via `MainScaffold.appBar` so every shell screen inherits the sticky header (logo left, bell + avatar right), matching HTML lines 122–133.
- Split navigation semantics: `context.go()` for bottom-nav tab switches only; `context.push()` for all forward drill-downs so the router stack grows and `pop()` works.
- Move `Logo (4).png` → `assets/images/arl_logo.png`; declare assets + Inter fonts in `pubspec.yaml`.

**Tech Stack:** Flutter 3.10+, Riverpod 2.5, go_router 14.2, Material 3.

**Manual verification only (no flutter test suite in this project).** Use `flutter analyze` + `flutter run -d chrome` for each verification step.

---

## Task 1: Asset Pipeline — Logo

**Files:**
- Move: `Logo (4).png` → `assets/images/arl_logo.png`
- Modify: `pubspec.yaml`

**Step 1: Move + rename the logo file**

```bash
mv "Logo (4).png" assets/images/arl_logo.png
```

Expected: `ls assets/images/` shows `arl_logo.png`.

**Step 2: Declare asset in pubspec.yaml**

Edit `pubspec.yaml`, replace trailing `flutter:` block with:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/arl_logo.png
```

**Step 3: Pub get**

Run: `flutter pub get`
Expected: `Got dependencies!` exit 0.

**Step 4: Verify analyze clean**

Run: `flutter analyze`
Expected: `No issues found!`

**Step 5: Commit**

```bash
git add pubspec.yaml assets/images/arl_logo.png
git commit -m "chore(assets): add ARL logo to assets pipeline"
```

---

## Task 2: Asset Pipeline — Inter Font (optional, do if fonts present)

**Files:**
- Check: `assets/fonts/`
- Modify: `pubspec.yaml`

**Step 1: Check font files exist**

Run: `ls assets/fonts/`
If empty → skip Task 2 entirely; fall back to system font. (HomeScreen already references `fontFamily: 'Inter'` — removing is optional.)

**Step 2: If Inter TTFs present, declare in pubspec.yaml**

Append under `flutter:`:

```yaml
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

**Step 3: `flutter pub get` + verify analyze clean**

**Step 4: Commit**

```bash
git add pubspec.yaml assets/fonts/
git commit -m "chore(fonts): declare Inter font family"
```

---

## Task 3: Build Shared `ArlAppBar` Widget

**Files:**
- Create: `lib/core/widgets/arl_app_bar.dart`

**Step 1: Create the widget**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

class ArlAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArlAppBar({super.key, this.showNotifDot = true});

  final bool showNotifDot;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ArlColors.cream,
        border: Border(bottom: BorderSide(color: Color(0xFFD4D2B4), width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: logo
                Image.asset(
                  'assets/images/arl_logo.png',
                  height: 32,
                  fit: BoxFit.contain,
                ),
                // Right: bell + avatar
                Row(
                  children: [
                    _CircleButton(
                      onTap: () => context.push(RouteNames.activity),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications_outlined,
                              color: ArlColors.charcoal, size: 22),
                          if (showNotifDot)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: ArlColors.gold,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: ArlColors.cream, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => context.push(RouteNames.profile),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: ArlColors.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'SK',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    );
  }
}
```

**Step 2: Verify analyze**

Run: `flutter analyze lib/core/widgets/arl_app_bar.dart`
Expected: `No issues found!`

**Step 3: Commit**

```bash
git add lib/core/widgets/arl_app_bar.dart
git commit -m "feat(ui): add shared ArlAppBar with logo + bell + avatar"
```

---

## Task 4: Inject `ArlAppBar` into `MainScaffold`

**Files:**
- Modify: `lib/core/widgets/main_scaffold.dart`

**Step 1: Add import + appBar**

Replace top of build():

```dart
import 'package:arl_app/core/widgets/arl_app_bar.dart';
// ...
return Scaffold(
  backgroundColor: ArlColors.cream,
  appBar: const ArlAppBar(),
  body: child,
  bottomNavigationBar: ...
```

**Step 2: Run app + verify logo appears on Home, Projects, Financials, Explore**

Run: `flutter run -d chrome`
Expected: Top-left shows ARL logo image on every shell tab. Bell + avatar on right.

**Step 3: Commit**

```bash
git add lib/core/widgets/main_scaffold.dart
git commit -m "feat(ui): mount ArlAppBar globally via MainScaffold"
```

---

## Task 5: Strip Duplicate Header From HomeScreen

**Files:**
- Modify: `lib/features/home/home_screen.dart`

**Step 1: Remove the inline header Row (WELCOME BACK / Sahil Kumar / bell / avatar)**

Keep only the project-selector dropdown + below-the-header body content. Header duties now live in `ArlAppBar`.

Replace the "── Header ──" Padding block with just the project selector pill, wrapped in a `Padding(EdgeInsets.fromLTRB(16,16,16,0))`.

**Step 2: Verify Home layout no longer has duplicate bell/avatar**

Run: `flutter run -d chrome`
Expected: Home shows ArlAppBar at top, then project selector, then portfolio card.

**Step 3: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "refactor(home): remove inline header, use global ArlAppBar"
```

---

## Task 6: Fix Navigation Semantics — `push` for Drill-Downs

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/home/widgets/quick_stats_row.dart`
- Modify: `lib/features/profile/profile_screen.dart`
- Modify: `lib/features/support/support_screen.dart`
- Modify: `lib/features/projects/projects_list_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/core/widgets/arl_app_bar.dart` (already uses push, verify)
- Keep `context.go()` in: `lib/core/widgets/main_scaffold.dart` (bottom-nav tabs)

**Step 1: Replace drill-down `context.go` → `context.push`**

Rule: if target is NOT one of `{home, projects, financials, explore}` → use `push`. If target IS a bottom-nav tab → keep `go`.

Sweep list:
- `home_screen.dart` → `activity`, `profile`, `projectSelector` → `push`
- `quick_stats_row.dart` → `financials` → KEEP `go` (bottom-nav tab)
- `profile_screen.dart _menuTile` → all sub-routes → `push`
- `support_screen.dart` → `newTicket`, ticket detail → `push`
- `projects_list_screen.dart` → `projectDetailPath` → `push`
- `project_detail_screen.dart` → `locationPath` → `push`

**Step 2: Guard every `pop()` with canPop fallback**

Bulk replace across back-button screens (13 files listed in report §5):

```dart
onPressed: () {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(RouteNames.home);
  }
},
```

Target files:
- `lib/features/activity/activity_screen.dart`
- `lib/features/documents/documents_screen.dart`
- `lib/features/exit/exit_screen.dart`
- `lib/features/gallery/gallery_screen.dart`
- `lib/features/profile/bank_details_screen.dart`
- `lib/features/profile/kyc_screen.dart`
- `lib/features/profile/security_screen.dart`
- `lib/features/projects/location_screen.dart`
- `lib/features/projects/project_detail_screen.dart`
- `lib/features/projects/project_selector_screen.dart`
- `lib/features/support/new_ticket_screen.dart`
- `lib/features/support/support_screen.dart`
- `lib/features/support/ticket_detail_screen.dart`

**Step 3: Verify analyze clean**

Run: `flutter analyze`
Expected: `No issues found!`

**Step 4: Manual nav smoke test**

Run: `flutter run -d chrome`
Walk each flow, verify back arrow returns to prior screen:
- Home → bell → Activity → back → Home ✓
- Home → avatar → Profile → KYC → back → Profile → back → Home ✓
- Projects → project card → Detail → Location → back → Detail → back → Projects ✓
- Profile → Support → New Ticket → back → Support → back → Profile ✓
- Profile → Exit → Cancel dialog → back → Profile ✓

**Step 5: Commit**

```bash
git add lib/features lib/core/widgets
git commit -m "fix(nav): use push for drill-downs, guard pop with canPop fallback"
```

---

## Task 7: Font Family Cleanup (contingent on Task 2)

**Files:**
- Modify: `lib/features/home/home_screen.dart` (has `fontFamily: 'Inter'`)
- Modify: `lib/core/theme/arl_text_styles.dart` (check)

**Step 1:** If Task 2 was skipped (no Inter TTFs), remove `fontFamily: 'Inter'` refs to avoid silent fallback warnings. Otherwise leave as-is.

**Step 2: Commit**

```bash
git add lib/
git commit -m "chore(typography): align font family declaration with assets"
```

---

## Task 8: Final Verification Pass

**Step 1: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

**Step 2: Hot restart + visual checklist**

Run: `flutter run -d chrome`

| Check | Pass criteria |
|---|---|
| Logo visible top-left Home | Yes |
| Logo visible on Projects tab | Yes |
| Logo visible on Financials tab | Yes |
| Logo visible on Explore tab | Yes |
| Bell icon tap → Activity + back works | Yes |
| Avatar tap → Profile + back works | Yes |
| Profile → KYC back works | Yes |
| Projects → Detail → Location back chain works | Yes |
| Bottom-nav tab switch does NOT stack | Yes (tab switch replaces) |
| Gallery back works | Yes |
| Exit screen back works | Yes |

**Step 3: If all checks pass, squash-merge branch**

```bash
git log --oneline
# verify commit chain
```

**Step 4: Update project status**

Append to `.claude/status.md`: "HTML-parity pass complete — logo, global header, nav stack fixed."

---

## Rollback

If any task breaks builds:

```bash
git reset --hard HEAD~1
```

Each task is isolated, one commit per task.

---

## Out of Scope (Follow-Ups)

- Activity notifications ↔ timeline toggle
- Notification dot dynamic state
- Project-selector header dropdown (currently HomeScreen-only)
- Pixel-level spacing audit per screen
