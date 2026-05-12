# ARL App vs Growize HTML Design — Investigation Report

**Date:** 2026-04-24
**Scope:** Why Flutter app does not match `Growize App Design.html`; logo missing top-left; back buttons non-functional.

---

## 1. HTML Design Inventory (source of truth)

17 pages, single-file prototype (`Growize App Design.html`, 1998 lines):

| # | Page ID | Purpose |
|---|---|---|
| 1 | page-home | Portfolio summary, progress cards, quick stats |
| 2 | page-projects | Projects list with tabs (all/gv/so/va) |
| 3 | page-financials | Risk/Return chart, earnings outlook, tabs |
| 4 | page-explore | 5-year projection |
| 5 | page-activity | Notifications + timeline toggle |
| 6 | page-profile | Avatar, menu list (KYC, Bank, Docs, etc.) |
| 7 | page-kyc | KYC details |
| 8 | page-bank-details | Bank info |
| 9 | page-documents | Vault files |
| 10 | page-support | Ticket list + raise button |
| 11 | page-ticket-detail | Ticket thread |
| 12 | page-new-ticket | Create ticket |
| 13 | page-security | Security settings |
| 14 | page-exit | Project exit flow |
| 15 | page-gallery | Photo grid (dark green bg) |
| 16 | page-location | Farm region map |
| 17 | page-project-selector | Global project filter |

**Global sticky header (lines 122–133)** — renders on every page:
- Left: `<img>` inline base64 PNG logo
- Right: bell icon + circular avatar button
- Style: `bg-arl-cream/95 backdrop-blur-md h-14 border-b`

**Bottom nav** (lines ~1394): 4 tabs — Home / Projects / Financials / Explore.

**Color tokens** (HTML tailwind config):
`primary #3C5152`, `accent #2E7D6E`, `gold #D4AF37`, `goldlight #F2DC6B`, `cream #FAFAF7`, `sand #E1DFC6`, `earth #C05640`, `charcoal #0F1A15`, `muted #6B7280`.

Font: Inter (Google Fonts).

---

## 2. Flutter Inventory

All 17 screens exist in `lib/features/**`. Routes in `lib/core/navigation/router.dart` cover all 17.

**Theme** (`lib/core/theme/arl_colors.dart`) — palette matches HTML. Good.

**MainScaffold** (`lib/core/widgets/main_scaffold.dart`) — has:
- `body: child`
- `bottomNavigationBar`
- **NO `appBar`. NO global header. NO logo widget anywhere.**

**HomeScreen** header — inline `Row` with text "WELCOME BACK" / "Sahil Kumar" + bell + avatar. No logo image.

---

## 3. Diff — HTML vs Flutter

| Area | HTML | Flutter | Gap |
|---|---|---|---|
| Global header w/ logo | Sticky on every page | Missing entirely | **CRITICAL** |
| Logo asset | Inline base64 PNG | `Logo (4).png` at project root, NOT in `assets/` | **CRITICAL** |
| `pubspec.yaml` assets | n/a | **No `assets:` section** | **CRITICAL** |
| Back nav | `showPage()` JS (any-to-any) | GoRouter `context.go()` (replaces stack) | **CRITICAL** |
| 4-tab bottom nav | Yes | Yes | Match |
| Color palette | Defined | Matches | Match |
| Inter font | `<link>` Google Fonts | `fontFamily: 'Inter'` refs but **fonts not declared in pubspec** | Broken |
| Per-screen arrow_back | Simple JS home-return | `IconButton` → `pop()` (no stack) | Broken |
| Project-selector header dropdown | Top-header button | HomeScreen-only button | Partial |
| Notification dot | Yes | Static icon only | Partial |
| Risk/Return 4-quadrant chart | Yes | Rebuilt (matches spec) | Match |
| Gallery date grouping | Yes | Yes | Match |
| 5-yr projection bars | Yes | Yes | Match |
| Profile menu tiles | Yes | Yes | Match |
| Exit confirmation dialog | JS alert | `AlertDialog` | Match |
| Project detail phases expand | Yes | Yes | Match |
| Financials tabs | Yes | Yes | Match |
| Activity notifications ↔ timeline toggle | Yes | Timeline only, no toggle | Partial |

---

## 4. Logo Not Visible — Root Cause

**Chain of failures:**

1. **File location wrong.** `Logo (4).png` sits at `C:/Users/Sahil/Downloads/ARL/arl_app/Logo (4).png` (project root). Flutter asset loader only reads paths declared in `pubspec.yaml` and packaged at build time.
2. **`pubspec.yaml` missing `assets:` block.** Current pubspec ends at `uses-material-design: true`. No `assets:` / `fonts:` declared → nothing bundled.
3. **`assets/images/` empty.** Directory exists but zero files inside.
4. **No widget renders a logo.** Grep of `Image.asset` / logo references across `lib/` returns zero hits. `MainScaffold` has no `AppBar`. `HomeScreen` has no logo `Image`.
5. **Filename unsafe.** `Logo (4).png` contains spaces + parens — Flutter asset paths should be snake_case (e.g., `arl_logo.png`).

**Result:** nothing to render, even if a widget tried.

---

## 5. Back Buttons Non-Functional — Root Cause

**GoRouter stack-replacement bug.**

- 13 screens have `IconButton(icon: Icons.arrow_back, onPressed: () => context.pop() / Navigator.pop(context))`.
- 12 navigation calls across codebase use `context.go(...)`, **0 use `context.push(...)`**.
- In GoRouter, `context.go(path)` **replaces** the current location — it does NOT push onto a nav stack.
- All shell routes (home, projects, financials, explore, gallery, documents, activity, profile) are **sibling children of one `ShellRoute`**. Navigating from Home → Gallery via `context.go()` replaces Home with Gallery. Stack depth = 1.
- Gallery's back button calls `pop()` → nothing to pop → silent no-op (or throws in debug).

**Concrete example flow:**
1. User on Home → taps bell → `context.go(RouteNames.activity)` → stack = `[Activity]`.
2. User on Activity taps back arrow → `Navigator.of(context).pop()` → pop fails, no prior route.

**Also affects:** Profile menu → KYC/Bank/Security/Exit/Support/Documents — all transitions use `context.go()`, so back buttons all dead.

---

## 6. Fix Plan — Three Options

### Option A — Direct code fix (recommended, fastest)

I can fix now without Figma. Required edits:

1. **Logo pipeline**
   - Move + rename: `Logo (4).png` → `assets/images/arl_logo.png`
   - Add to `pubspec.yaml`:
     ```yaml
     flutter:
       uses-material-design: true
       assets:
         - assets/images/arl_logo.png
     ```
   - Create shared `ArlAppBar` widget with `Image.asset('assets/images/arl_logo.png', height: 32)` + notification + avatar.
   - Inject `ArlAppBar` into `MainScaffold` as the `appBar`, so every shell screen gets it.
   - Remove duplicate HomeScreen inline header.

2. **Back button navigation**
   - Replace every `context.go(...)` used for forward nav into sub-screens with `context.push(...)`.
   - Keep `context.go()` only for bottom-nav tab switches (tabs should replace, not stack).
   - Specifically: Profile → KYC/Bank/Security/Exit/Documents/Support, Home → Activity, Projects → ProjectDetail → Location, Support → NewTicket/TicketDetail, ProjectSelector entry.
   - Guard each `pop()` with `if (context.canPop()) context.pop(); else context.go(RouteNames.home);` for safety.

3. **Inter font declaration** (bonus, same edit pass)
   - Add `fonts:` section to `pubspec.yaml` pointing at `assets/fonts/Inter-*.ttf` (fonts currently referenced but undeclared).

**Effort:** ~1–2 hours. Zero Figma needed. HTML is already a pixel-level spec.

### Option B — Figma / Wireframe first

Only needed if you want **different** visuals from HTML. Given HTML already encodes every screen with hex colors + Tailwind classes + final copy, Figma would be redundant — it would just re-describe the HTML. **Skip unless you're redesigning.**

### Option C — Hybrid

Use HTML as-is for static screens; get Figma only for a new/undesigned flow (e.g. onboarding, KYC upload steps). Not relevant here — all 17 screens fully specified.

---

## 7. Recommendation

Proceed with **Option A**. HTML prototype is exhaustive. I can fix logo + back buttons + header consolidation in one pass. Will also surface remaining cosmetic gaps (activity toggle, notif badge state, project-selector header dropdown) as follow-ups.

**Next step:** approve Option A and I execute the edits.
