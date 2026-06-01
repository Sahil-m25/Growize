# Growize V32 Visual Check — Final Pass Attempt
**Date:** 2026-05-19 (file dated 2026-05-17 per spec)
**Tester:** Claude (Cowork)
**Build under test:** Flutter web @ http://localhost:5000/
**Expected start state:** Home dashboard via `ARL_DEV_BYPASS=true`

---

## VERDICT: 🔴 RED — STOP CONDITION HIT, RUN ABORTED AT STEP 1

The user-specified gate ("If you see login OR blank screen, STOP and report — the unblock didn't work.") triggered. Both failure modes were observed back-to-back.

---

## Step 1 — Home dashboard load attempt: ❌ FAIL

### 1a. First load: blank white screen
On initial `navigate http://localhost:5000/`:

- Page title sets to **"Growize — ARL Investor Portal"** (head correct)
- Body remains visually empty (white) after 8s, 13s, and 18s waits
- DOM contains 6 children but ZERO Flutter render surfaces:
  - `SCRIPT`, browser-extension DIVs, a non-Flutter `BUTTON`, claude-agent overlays
  - **No `<flutter-view>`, no `<flt-glass-pane>`, no `<flt-scene-host>`**
- Console: only DDC module loader INFO ("DDC is about to load 1121/1121 scripts with pool size = 1000"). No Flutter init log, no error.
- `window._flutter.loader` and `window._flutter.buildConfig` ARE defined → loader script ran
- `window.$dartRunMain` IS a function → entry point compiled and registered
- BUT main is never invoked automatically — Flutter never paints

**This is exactly DEF-V32-VIS-08 (page does not auto-run on load). It is NOT resolved in the current build.**

### 1b. Manual `$dartRunMain()` invocation: landed on `/#/auth`, not `/#/home`
To collect more diagnostic data I executed `window.$dartRunMain()` directly via JS console:

- Flutter rendered after ~6s
- Page URL became `http://localhost:5000/#/auth`
- Visible UI: Growize logo, "Investment Portal by AgResearch Labs", and a full-width **Sign In** button at the bottom with "By continuing, you agree to our Terms of Service" disclaimer
- **No home dashboard. No bottom nav. No project tiles. Auth gate is in effect.**

**This means `ARL_DEV_BYPASS=true` is either not wired to the auth router, not being read at compile/run time, or is being overridden by AuthGuard logic.**

Screenshot evidence:
- `screenshot-1779175510790.jpg` (auth/sign-in screen after manual main invocation)
- Earlier blank-white captures from initial navigation are in the Chrome MCP session log (IDs `ss_8719i7wk9`, `ss_89301b995`, `ss_7394l9c8p`)

---

## V32-VIS defect resolution status

| ID | Description | Status | Evidence |
|---|---|---|---|
| DEF-V32-VIS-01 | Projects tile tap opens detail | ⏸ NOT TESTABLE | Can't reach Projects tab — auth gate |
| DEF-V32-VIS-02 | Explore tile tap opens detail | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-03 | Financials sub-tab toggle | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-04 | Explore has 3 filter pills | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-05 | Explore tiles fully populated | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-06 | No RenderFlex errors on detail | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-07 | Detail body scrolls | ⏸ NOT TESTABLE | Same |
| DEF-V32-VIS-08 | Page auto-loads without manual main | ❌ **CONFIRMED STILL FAILING** | Initial load blank; only paints after manual `$dartRunMain()` |

7 of 8 are NOT TESTABLE because the precondition (auth bypass to home) is broken. 1 of 8 (-08) is directly observed as still failing.

---

## UI Catalog walkthrough (28 rows / 14 screens)

**Result: 0 PASS / 0 FAIL / 28 SKIPPED — all skipped due to Step 1 gate failure.**

| # | Screen | Status |
|---|---|---|
| 1 | home — landing | ⏸ SKIP (auth gate) |
| 2 | projects-list | ⏸ SKIP |
| 3 | project-detail | ⏸ SKIP |
| 4 | view-area | ⏸ SKIP |
| 5 | photos | ⏸ SKIP |
| 6 | photo-fullscreen | ⏸ SKIP |
| 7 | explore | ⏸ SKIP |
| 8 | explore-detail | ⏸ SKIP |
| 9 | share-modal | ⏸ SKIP |
| 10 | financials | ⏸ SKIP |
| 11 | documents | ⏸ SKIP |
| 12 | activity | ⏸ SKIP |
| 13 | profile | ⏸ SKIP |
| 14 | celebration | ⏸ SKIP |

---

## Console output (full)

Only two messages were captured across the entire session, both informational:

```
[INFO] http://localhost:5000/ddc_module_loader.js:1014  DDC is about to load 1/2 scripts with pool size = 1000
[INFO] http://localhost:5000/ddc_module_loader.js:1014  DDC is about to load 1121/1121 scripts with pool size = 1000
```

No errors, no warnings, no Flutter framework logs, no AuthGuard / DevBypass diagnostic logs — silent failure.

---

## Multi-viewport / bonus checks

Not exercised. Step 1 gate prevents any meaningful viewport testing — at every width the page is blank or shows the same Sign In screen.

---

## New defects logged

### DEF-V32-FINAL-01 — Flutter entry point not auto-invoked on cold load
- **Severity:** Critical (blocker)
- **Repro:** Cold-load `http://localhost:5000/` → page stays blank indefinitely; `window.$dartRunMain` is defined but never called by `flutter_bootstrap.js` / loader.
- **Workaround:** Manually evaluate `window.$dartRunMain()` in DevTools console to bring up the UI.
- **Likely cause:** Custom or missing `flutter_bootstrap.js`; or `loadEntrypoint` callback chain broken. The standard Flutter web bootstrap should automatically invoke `dartRunMain` after `didCreateEngineInitializer` / `runApp`.
- **Probable owner:** Whoever last edited `web/index.html` or the bootstrap pipeline.

### DEF-V32-FINAL-02 — `ARL_DEV_BYPASS=true` not honored; AuthGuard routes to `/#/auth`
- **Severity:** Critical (blocks all V32 visual verification)
- **Repro:** With the dev bypass env var supposedly set true, after Flutter renders the URL is `http://localhost:5000/#/auth` and the Sign In screen is shown.
- **Likely causes (in priority order):**
  1. `ARL_DEV_BYPASS` is a Dart `String.fromEnvironment` flag that needs to be passed at compile time via `--dart-define=ARL_DEV_BYPASS=true`, not as a runtime env var. If the dev server was started without `--dart-define`, the flag will be the empty string and any `bool.fromEnvironment` reads will be `false`.
  2. AuthGuard / router redirect runs before the bypass check
  3. Bypass flag is read but the AuthGuard still requires a non-null user session
- **Verify by:** Re-running the dev server with `flutter run -d chrome --web-port=5000 --dart-define=ARL_DEV_BYPASS=true` (or equivalent build), and grepping the Dart codebase for `ARL_DEV_BYPASS` / `bool.fromEnvironment` to confirm the read pattern.

---

## Recommended next steps before resuming the visual pass

1. Fix DEF-V32-FINAL-01 (auto-bootstrap). Verify cold-load paints UI in <10s with no manual JS intervention.
2. Fix DEF-V32-FINAL-02 (bypass actually lands on home). Verify URL is `/#/home` and the bottom nav is visible.
3. Re-run this exact test plan. The 28 catalog rows + 8 V32-VIS defect checks can all be exercised once the gate clears.

---

## Sandbox / tooling notes

- The Cowork workspace bash sandbox is **out of disk** ("No space left on device" on `useradd`). The `outputs/visual-check-final-v32/` directory could not be created via bash. Screenshots from Chrome MCP land at `…\agent\local_ditto_…\outputs\`. No tracker mutation was attempted because the xlsx skill would also hit the same disk limit.
- No `outputs/v32_visual_results.csv` was written because there is nothing to record beyond the universal SKIP. (Trivially, all 28 rows = SKIP, gated_by = DEF-V32-FINAL-01 + DEF-V32-FINAL-02.) Happy to emit the CSV stub if useful — just say the word.
- Git was not touched.
- Session bypass not broken (no logout) because we never reached an authenticated state to break.

---

## TL;DR

The "both blockers from prior attempt are resolved" claim does not hold against this build. The Flutter bootstrap still does not auto-invoke `main`, and even after manual invocation the router lands on `/#/auth` rather than `/#/home`. **🔴 RED — do not ship; do not resume catalog testing until the two FINAL defects above are fixed.**
