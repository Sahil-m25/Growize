# Parity Patch Plan — Project Detail + Profile / Settings cluster

**Date.** 2026-05-12 (research pass).
**Mode.** Read-only spec — no code changed yet.
**Sources.**
- HTML reference: `Growize App Design.html` (1998 LOC).
- Flutter source: `lib/features/projects/project_detail_screen.dart` (869 LOC) + `lib/features/profile/*.dart` + `lib/features/documents/documents_screen.dart`.
- Design tokens: `CLAUDE.md` (primary `#3C5152` / accent `#2E7D6E` / gold `#D4AF37` / cream `#FAFAF7` / sand `#E1DFC6` / earth `#C05640` / charcoal `#0F1A15` / muted `#6B7280`).

---

## 🚨 P0 — global blocker across every screen in scope

**Inter font is NOT bundled.** `pubspec.yaml` L69-78 has the entire `fonts:` block commented out. `lib/core/theme/arl_theme.dart` references `fontFamily: 'Inter'` in 14 places (theme + 12 text-style entries). Result: Flutter falls back to the platform default (Roboto on Android, San Francisco on iOS). Every screen — including the two tracks below — looks "off" because typography differs from the HTML prototype.

**Fix.**
1. Add Inter TTF files to `assets/fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf` (open-source download from Google Fonts).
2. Uncomment the `fonts:` block in `pubspec.yaml` L69-78.
3. `flutter clean && flutter pub get && flutter build apk --release`.

Effort: **S** (mechanical), but unblocks all visual parity work. Land this first.

---

# Track 1 — Project Detail

## 1.1 HTML reference

Located in `Growize App Design.html` L956-1010 (within the `page-projects` div at L302). The HTML treats project detail as a slide-in section nested in the projects page — not a separate route, but the visual structure is well-defined.

**Visible top-to-bottom on the HTML detail view:**
1. Back chevron + "Back to All Projects" link (top-left).
2. **Hero card** — gradient banner (project brand color → 70% alpha), rounded-15, padding 16.
   - Left: 40×40 white-20% rounded-8 box with project initials in white bold.
   - Right of initials: project name (white, bold, 16-18px) + location subtitle (white-80%, 11-12px) e.g. "Karnataka · Month 4 of 60".
   - Far right: status pill — accent-25% bg + accent text for `operational`; earth-25% bg + earth text for `pending`. Rounded-12, py-1 px-2, text 9-10px.
3. **Stats triad** (3-column grid below hero, `gap-2 mt-4`):
   - Tile 1 "Your Units" — units number in bold charcoal 16px, label muted 9-10px.
   - Tile 2 "Month" — `monthOfContract/totalMonths` (e.g. `4/60`).
   - Tile 3 "Invested" — `Money.inr(capital_invested + token_advance_amount)`.
   - Each tile: white bg, rounded-15, padding 12, sand 1px border.
4. **Contract Progress bar** — full-width sand track, brand-color fill `width: progressPercent%`. Right-aligned `<progressPercent>%` label in primary bold 10-11px.
5. **Per-unit price row** — single line "Invested · Per-unit price" with two values. (HTML L975-979 has this row; Flutter MISSING.)
6. **Phases / Milestones timeline** — expandable accordion list with phases:
   - Phase pill (DONE = accent / IN PROGRESS = gold / UPCOMING = muted) + phase title.
   - Sub-tasks list under each phase (1.1, 1.2, etc. numbered like HTML).
   - Tap to expand/collapse — chevron rotates.
7. **Bottom action banner** (`pending` projects only): earth-10 bg + earth border, "₹12L payment pending — payouts on hold" + warning icon.

## 1.2 Flutter current state

`lib/features/projects/project_detail_screen.dart`:
- L83 `Scaffold` w/ AppBar (back button + actions: gallery, location). **HTML has no AppBar** — back chevron is inline in the hero, no separate AppBar.
- L182-198 `_Hero` widget — initials + name + cropEmoji + cropType + location. Hero IS gradient but with project brand color only (no alpha fade).
- L213-260 **3-tile stats grid** ("Your Units" / "Month" / "Invested") via `Consumer` reading `investorAllocationProvider`. ✓ Present and matches HTML triad.
- ~L320 Contract Progress bar — present, uses `FractionallySizedBox`. ✓.
- **NO `Per-unit price` row.** ❌ HTML has it.
- L450+ Phases timeline — driven by `projectPhasesProvider`. Expandable per phase via `_expandedPhases` set. Sub-tasks DO render numbered 1.1/1.2/etc.
- Pending banner — present in `_Hero` (`isPending` branch).
- Hardcoded `_projectPhases` constant at file bottom (L800+) — fallback if no DB phases. Has 4 phases (Land Prep / Setup / Cultivation / Harvest).

## 1.3 Project Detail — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| Back chevron inline in hero (no AppBar) | `AppBar` with back arrow + gallery + location action icons | Layout drift — HTML has no separate top bar; back+actions are inline | Remove `AppBar`; add a custom `_HeroTopBar` row inside `_Hero` with `IconButton(arrow_back)` left + 2 action icons right. File: `project_detail_screen.dart` L130-180 | M |
| Hero gradient: brand color → brand@70% alpha | Solid brand color (no fade) | Visual drift | Wrap `Container.decoration.gradient: LinearGradient(colors: [brand, brand.withValues(alpha:0.7)])`. File: `_Hero` widget L500-ish | S |
| Hero "Karnataka · Month 4 of 60" subtitle (single line, location + month) | "location" only; "Month" lives in the separate stats triad | Layout drift — HTML combines into subtitle | Update `_Hero` subtitle to `'${project.location} · Month ${project.monthOfContract} of ${project.totalMonths}'`. File: `_Hero` L530-ish | S |
| Stats triad — 3 tiles equal width | Present with same 3 tiles | ✓ matches | — | — |
| **`Per-unit price` row** (text row: "Invested ₹75L · Per-unit ₹25L") | MISSING | Missing section (P1) | Add `_BreakdownRow` after stats triad. Shows `Invested ${Money.inr(invested)} · Per-unit ${Money.inr(unitPrice)}`. File: insert after L260 | S |
| Contract Progress bar | ✓ present | Visually present but fill colour: HTML uses brand color; Flutter check colour | Verify `valueColor` uses `brand`, not `ArlColors.primary`. File: progress bar widget | S |
| Phases timeline — accordion with rotating chevron | Present, but chevron is `Icon(Icons.expand_more)` — no rotation animation | Visual drift (small) | Wrap chevron in `AnimatedRotation(turns: isExpanded ? 0.5 : 0, ...)`. File: phase widget L600-700 | S |
| Phase pill colours: DONE=accent, IN PROGRESS=gold, UPCOMING=muted | ✓ matches via `_phaseColor` switch | ✓ matches | — | — |
| Sub-tasks numbered "1.1" / "1.2" | ✓ matches | ✓ matches | — | — |
| Pending project banner ("₹12L payment pending") | Present in `_Hero` `isPending` branch | ✓ matches | — | — |
| Hardcoded `_projectPhases` fallback (L800+ in file) | Present | Data binding drift — should fallback to empty/sample state, not hardcoded mock phases | Remove constant; render empty-state placeholder if `phases.isEmpty`. File: `project_detail_screen.dart` L800-869 | M |
| Inter font on all text | system default (P0) | Inter not bundled | See P0 above | S |

**Track 1 effort summary:** 1 M (AppBar restructure) + 1 M (remove mock phases) + 5 S = **medium-light** track. Land top-to-bottom for visual parity.

---

# Track 2 — Profile + sub-screens

## 2.1 Profile (`page-profile` HTML L1075-1099)

### HTML inventory

1. Gradient header — primary→accent linear gradient, `p-6 pb-8` (~24/32 px padding). Rounded bottom corners.
   - Avatar — 64×64 white-20% circle with initials.
   - Name + email below.
2. "Stats strip" — small 2-column row below avatar (e.g. "3 Projects · ₹3.92Cr invested"). Subtle white-70 text.
3. **Active Projects card** — single white card listing project names separated by `·` (e.g. "Pineapple · Samsung · Xiaomi").
4. **Account section** — `_sectionTitle` "Account" muted uppercase + 4 menu tiles:
   - KYC Details (badge "Verified")
   - Bank Details
   - Documents
   - Security
5. **Support section** — `_sectionTitle` "Support" + 2 tiles:
   - Help & Support
   - Replay Tour
6. **Sign Out** — destructive red text-only button on white card (NOT a filled Material destructive button).
7. App version footer.

### Flutter inventory (`profile_screen.dart`)

- Gradient header — primary→accent LinearGradient, EdgeInsets.all(20). ✓ matches.
- Avatar — circle with initials. ✓.
- Name + email. ✓.
- "Active Projects" card (L130-180). ✓.
- "Account" section: KYC (with "Verified" badge) + Bank Details + Documents + Security. ✓ matches.
- "Support" section: Help + Replay Tour. ✓.
- **Sign Out** — `ElevatedButton` with Material destructive red. ❌ HTML uses text-only on white card.

### Profile — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| Header padding 24/32 px | EdgeInsets.all(20) | Visual drift | Change to `EdgeInsets.fromLTRB(24, 24, 24, 32)`. File: `profile_screen.dart` header `Container` | S |
| Stats strip below avatar ("3 Projects · ₹3.92Cr invested") | (verify present — search code) | Possibly missing | Add subtitle row under name in header. Pull from `portfolio_summary`. File: header section | S |
| Sign Out — text on white card | ElevatedButton (Material red) | Visual drift | Replace with `Container(white, sand border, rounded-15)` wrapping `TextButton(red text)`. File: `profile_screen.dart` near bottom | S |
| Inter font | system default | P0 | See P0 | — |

**Profile effort:** 3 S.

## 2.2 KYC (`page-kyc` HTML L1100-1134)

### HTML inventory

1. AppBar — back arrow + "KYC Details" title.
2. **Top status banner** — circular shield icon (accent-15% bg) + green "Verified" badge + line "Your KYC is complete".
3. Field rows — Full Name / Date of Birth / PAN / Aadhaar — each as label+value rows in a single white card.
4. "Re-verify" CTA if rejected (conditional, not shown when verified).

### Flutter inventory (`kyc_screen.dart`)

- AppBar — ✓ present (back + "KYC Details" title centered-false).
- **Top status banner — MISSING.** No circular shield + verified badge as a hero card.
- Field rows — likely present (need to verify in remaining lines of `_kycField` helper).
- No conditional "Re-verify" CTA.

### KYC — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| **Top status banner** with shield icon + Verified badge + status text | MISSING | Missing section (P1) | Add `_KycStatusBanner` widget at top: `Container(white, rounded-15)` with 48px shield icon (accent-15% bg circle), "KYC Verified" + sub-text "Submitted on $date". File: `kyc_screen.dart` insert after AppBar | M |
| AppBar title centered? | centered-false | Layout drift (HTML left-aligns title to right of back arrow which is the same) | ✓ matches if Flutter uses `centerTitle: false` (it does). | — |
| Field rows: Full Name / DOB / PAN / Aadhaar | Likely present | Verify all 4 are bound to real data | Verify in `_kycField` calls. File: `kyc_screen.dart` body | S |
| "Re-verify" CTA when rejected | Missing | Missing conditional UI | Add at bottom: `if (status == 'rejected') ElevatedButton('Re-submit KYC')`. File: `kyc_screen.dart` body tail | S |
| Inter font | system default | P0 | See P0 | — |

**KYC effort:** 1 M + 2 S.

## 2.3 Bank Details (`page-bank-details` HTML L1135-1168)

### HTML inventory

1. AppBar — back + "Bank Details".
2. **Account card** — single white card showing:
   - Bank icon + name (e.g. "HDFC Bank")
   - Account masked ("XXXX-XXXX-1234")
   - IFSC
   - Holder name
   - Verified badge (green) if `kyc_status='verified'`
3. **"Update Bank Account" CTA** — primary button.
4. Conditional pending request banner — sand-tint, "Change pending review".

### Flutter inventory (`bank_details_screen.dart`)

- AppBar — ✓ present.
- Bank fields shown — ✓ present (lines 60-80 show extraction).
- Verified badge — present via `isVerified` flag.
- Update CTA — present (opens modal via `_showRequestChangeModal`).
- Pending request banner — present via `hasPendingRequest`.

### Bank Details — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| Account card structure | Present | Verify visual: HTML uses single rounded-15 white card with subtle sand divider rows between fields | Verify card uses `Divider(color: ArlColors.sand)` between fields, not borders. File: `bank_details_screen.dart` field list | S |
| Verified badge (green) | Present via `isVerified` | ✓ matches | — | — |
| Update Bank Account CTA | Present | Verify button uses "gradient-primary" rounded-15 style (HTML buttons all use this) | Replace ElevatedButton with `Container(decoration: LinearGradient([primary, accent]))` wrapping `InkWell`. File: bank CTA section | S |
| Pending request banner — sand tint | Present | Verify color uses `ArlColors.sand.withValues(alpha:0.5)` not a generic warning yellow | Verify decoration. File: pending banner | S |
| Inter font | system default | P0 | See P0 | — |

**Bank effort:** 3 S.

## 2.4 Documents (`page-documents` HTML L1169-1241)

### HTML inventory

1. AppBar — back + "Documents".
2. **6 accordion sections** (fixed order, always rendered even when empty):
   1. Legal Agreements
   2. Due Diligence & Audits
   3. Insurance
   4. Project Updates
   5. Financial Statements
   6. Upkeep
3. Each section: white card rounded-15, sand border, accordion chevron right.
4. Inside each: doc list with name + uploaded date + download icon.
5. Empty sections still show the accordion header with "No documents yet" inside.

### Flutter inventory (`documents_screen.dart`)

- AppBar — ✓.
- **4 sections** (not 6): `agreement` / `contract` / `kyc` / `other`. Bucketed by `doc.category` from `documents.doc_type` column (CHECK: `agreement|contract|kyc|other`).
- Empty sections HIDDEN (`if (sections.isEmpty) return [_emptyState()]`).
- `_Accordion` widget with white card, sand border, rounded-15. Chevron present but no rotation.

### Documents — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| 6 fixed sections (Legal Agreements / Due Diligence & Audits / Insurance / Project Updates / Financial Statements / Upkeep) | 4 sections (agreement/contract/kyc/other) | **Schema + UX mismatch (L)** — `documents.doc_type` CHECK only allows 4 values | Two-stage fix: (a) migration to widen CHECK to 6 values; (b) update `documents_screen.dart` `order` tuple list to match HTML. File: new migration `026_documents_doc_type_expand.sql` + `documents_screen.dart:_group` | L |
| Empty sections shown with "No documents yet" placeholder | Empty sections hidden | Layout drift | Modify `_group`: always emit all 6 sections, render empty placeholder inside `_Accordion` if `items.isEmpty`. File: `documents_screen.dart:_group` + `_Accordion` | M |
| Chevron rotation on expand | Static chevron | Visual drift (small) | Wrap chevron in `AnimatedRotation(turns: isOpen ? 0.5 : 0)`. File: `_Accordion` build | S |
| Inter font | system default | P0 | See P0 | — |

**Documents effort:** 1 L + 1 M + 1 S.

## 2.5 Security (`page-security` HTML L1289-1308)

### HTML inventory

1. AppBar — back + "Security".
2. **Authentication card** — single white card rounded-15 with **3 rows** separated by sand dividers:
   - Row 1: Biometric Login icon (fingerprint, accent-15% bg circle) + label + "Enabled" subtext + toggle switch (accent-bg pill, white knob).
   - Row 2: App PIN icon (smartphone, primary-10% bg circle) + label + "Set" subtext + chevron right (nav to set/change PIN).
   - Row 3: Notifications icon (bell, gold-15% bg circle) + label + "On" subtext + toggle switch.
3. **Login History card** — separate white card listing recent login events (device + time).

### Flutter inventory (`security_screen.dart`)

- AppBar — ✓.
- **2 rows only**: Biometric Login + Face ID (both as toggles using state `_biometricEnabled`, `_faceIdEnabled`).
- ❌ App PIN row missing entirely.
- ❌ Notifications row missing entirely.
- ❌ Login History card missing entirely.

### Security — Delta table

| HTML element | Flutter state | Gap | Fix proposal | Effort |
|---|---|---|---|---|
| Single Authentication card with 3 rows | 2 separate cards (Biometric / Face ID) | **Major layout drift (M)** — content + grouping wrong | Consolidate into one `Card` containing 3 `_SecurityRow` widgets separated by `Divider(color: ArlColors.sand)`. File: `security_screen.dart` body | M |
| Row 1: Biometric Login + toggle | Present | ✓ matches (after consolidation) | — | — |
| **Row 2: App PIN + chevron-right (nav)** | MISSING | Missing functional row | Add `_SecurityRow` with `Icons.smartphone`, route to a new `/security/pin` screen (or no-op stub for now). File: `security_screen.dart` | M (needs new sub-screen) |
| **Row 3: Notifications + toggle** | MISSING | Missing | Add `_SecurityRow` with `Icons.notifications_outlined`, toggle state stored in Hive (`notifications_enabled`). File: `security_screen.dart` | S |
| Face ID toggle | Present (not in HTML) | Extra row in Flutter | Remove Face ID row (the iOS pattern; not in HTML scope). File: `security_screen.dart` | S |
| **Login History card** | MISSING | Missing section | Add separate `_LoginHistoryCard` below Authentication card. Initially placeholder ("History coming soon") since no `login_history` table exists. File: `security_screen.dart` body tail | M (or M+L if backend table) |
| Inter font | system default | P0 | See P0 | — |

**Security effort:** 2 M + 1 S + 1 M (or L) + 1 S = **biggest screen** in Track 2. Land last.

---

# Effort summary per screen

## Track 1 — Project Detail
| Item | Effort |
|---|---|
| AppBar restructure (back inline in hero) | M |
| Remove hardcoded `_projectPhases` mock | M |
| 4× small visual fixes (gradient fade, subtitle, progress fill, chevron rotation) | 4×S |
| Add `Per-unit price` row | S |
| **Sum** | **2M + 5S** |

## Track 2 — Profile + sub-screens
| Screen | Effort |
|---|---|
| Profile shell (padding, stats strip, sign-out card) | 3S |
| KYC (top status banner + re-verify CTA) | 1M + 2S |
| Bank Details (gradient CTA + divider styling) | 3S |
| **Documents (6 sections + always-show)** | **1L + 1M + 1S** |
| **Security (consolidate card + App PIN + Notifications + Login History)** | **3M + 2S + 1L (optional history table)** |
| **Track 2 sum** | **1L + 5M + 11S** |

## Ranked priority (recommended landing order)

1. **P0 — Inter font bundling** (1×S, blocks everything).
2. **Track 1 — Project Detail** small fixes — biggest visual wins, low effort.
3. **Profile shell** — cosmetic only.
4. **Bank Details** — cosmetic only.
5. **KYC top banner** — adds missing functional reassurance for verified users.
6. **Documents 6-section expansion** — needs schema migration + UI rewire (real work).
7. **Security card consolidation** + App PIN + Notifications + Login History — most work, save for last.

---

# Mismatch counts per screen (snapshot)

- Project Detail: **8 mismatches** (1 missing section, 1 missing row, 1 mock-data, 5 visual drifts).
- Profile: **3 mismatches** (padding, stats strip, sign-out style).
- KYC: **2 mismatches** (top status banner missing, re-verify CTA missing).
- Bank Details: **3 mismatches** (divider style, CTA style, banner color).
- Documents: **3 mismatches** (4-vs-6 sections, hidden empties, chevron rotation).
- Security: **5 mismatches** (card consolidation, missing App PIN, missing Notifications, extra Face ID, missing Login History).

**Total: 24 mismatches across 6 screens.** Plus 1 global P0 (Inter font).

---

# Patch dependency notes

- Inter font (P0) is non-negotiable to attempt before any subjective parity check. Without it, every "looks off" perception is dominated by typography drift, not the structural issues catalogued above.
- Documents 6-section expansion needs migration `026_documents_doc_type_expand.sql` BEFORE the screen UI change ships (UI references the new doc_types).
- Security Login History needs either a stub (placeholder text) OR a new `login_events` table — flag this as the only place we'd need backend work.
- All other patches are pure Flutter file edits, mostly within a single file each.
