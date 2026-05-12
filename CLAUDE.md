# arl_app — Project Context

ARL Investor Portal (Growize). Flutter mobile + web app for agri-investment portfolio tracking.

## Stack
- Flutter 3.10+ / Dart 3.0+
- Riverpod (state)
- GoRouter (nav)
- Supabase (backend, auth, db)
- Hive (offline cache)
- Inter font

## Source of Truth (design)
**`Growize App Design.html`** at project root — single-file HTML/Tailwind prototype, 17 pages. Flutter must match pixel/behavior parity.

Key tokens (see HTML tailwind config):
- `primary #3C5152` `accent #2E7D6E` `gold #D4AF37` `goldlight #F2DC6B`
- `cream #FAFAF7` `sand #E1DFC6` `earth #C05640` `charcoal #0F1A15` `muted #6B7280`

## Layout
```
lib/
├── main.dart, app.dart
├── core/         (theme, router, supabase client, shared widgets)
└── features/
    ├── activity/    auth/        documents/   exit/
    ├── explore/     financials/  gallery/     home/
    ├── onboarding/  profile/     projects/    support/
```

## Active Concerns
- HTML→Flutter parity gap. See `.claude/decisions/2026-04-24_html-parity-gap.md`.
- Logo `Logo (4).png` must be in `assets/` + declared in `pubspec.yaml`.
- Inter font must be declared in pubspec (currently referenced but not bundled).
- Back nav uses GoRouter `context.go()` — replaces stack. Use `push` when stack preservation needed.

## Build / Verify
```
& C:\flutter\bin\flutter.bat pub get
& C:\flutter\bin\dart.bat analyze lib
& C:\flutter\bin\flutter.bat run -d chrome
```
PowerShell preferred on Windows. Flutter installed at `C:\flutter\`.

## Conventions
- Riverpod providers in `core/` or feature-level `providers.dart`
- Screen files: `<feature>_screen.dart`
- Widgets in `widgets/` subfolder per feature
- No emoji in code/comments
- Match HTML design exactly — do not invent new layout

## Workflow
- Phase gates per global CLAUDE.md (Ideate→Plan→Implement→Verify→Ship)
- Log decisions to `.claude/decisions/`
- Log debug iterations to `.claude/iterations/`
- Update `.claude/status.md` when phase shifts
- Update `.claude/INDEX.md` for every new decision/iteration file
