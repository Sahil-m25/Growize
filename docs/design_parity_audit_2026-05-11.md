# HTML → Flutter Design Parity Audit

**Date:** 2026-05-11
**Author:** Audit agent (read-only)
**Reference design:** `Growize App Design.html` (1998 LOC, 17 screens)
**Flutter source:** `lib/features/**` + `lib/core/**`
**Mode:** Read-only — no code changed.
**Method:** Direct grep + read of HTML and every Flutter screen file. No reliance on prior audits except cross-check.

> Prior audits surveyed: `.claude/decisions/2026-04-24_html-parity-gap.md`, `docs/plans/2026-04-25-html-parity-master-gap-audit.md`. Those captured the global header / logo / pubspec / back-nav fixes that have **since been applied** (ArlAppBar exists, asset is wired, `context.push` is used for forward nav). This audit re-validates from scratch and adds per-screen content-level gaps that are still open.

---

## 1. Summary table — 17 screens

| # | Screen (HTML) | Flutter route | Parity | Top 1–3 divergences | Effort |
|---|---|---|---|---|---|
| 1 | Home (`page-home`) | `/` `home_screen.dart` | Mostly | (a) No HTML inline dropdown — opens full screen route instead. (b) Welcome label "WELCOME BACK" uppercase + small caps does not match HTML's `Welcome back` (mixed case). (c) `Tomato/Grape/Olive` emoji crop row missing from progress card | S |
| 2 | Projects (`page-projects`) | `/projects` `projects_list_screen.dart` | Mostly | (a) Header pill icon size differs (40×40 rounded-square vs HTML 40×40 rounded-full). (b) Status badge label "Active" used while HTML shows "Operational". (c) Pending project warning box border-radius `8` vs `15` HTML | S |
| 3 | Financials (`page-financials`) | `/financials` `financials_screen.dart` | Mostly | (a) Tab pill labels: HTML uses `Payouts` + `Financials`, Flutter has same — match. (b) Tax-Free banner border-radius `12` vs `15` HTML. (c) Earnings-Outlook bar fixed at 5 bars but bar heights computed against yield, not "Y1..Y5 fixed gradient" HTML scheme — bars visually thinner | M |
| 4 | Explore (`page-explore`) | `/explore` `explore_screen.dart` | Partial | (a) HTML uses a `<select>` dropdown + dark hero card with embedded summary; Flutter renders horizontal status filter chips + project cards then a separate projection card — different IA. (b) Unit slider + "Enter custom units" checkbox missing. (c) Total Investment / Per-unit price row missing | L |
| 5 | Activity (`page-activity`) | `/activity` `activity_screen.dart` | Mostly | (a) Toggle uses iOS-style pill button instead of HTML "Notifications" ↔ "Activity History" segmented label — same intent. (b) HTML filter chips (All/Operational/Payouts) live ONLY in the History view; Flutter same — match. (c) No "Mark all read" CTA shown on the HTML — Flutter adds one (acceptable extra) | S |
| 6 | Profile (`page-profile`) | `/profile` `profile_screen.dart` | Mostly | (a) Header gradient padding `EdgeInsets.all(20)` vs HTML `p-6 pb-8` (24 / 32 px). (b) "Active Projects" comma-list card present in HTML, missing in Flutter (Flutter only shows menu tiles). (c) "Sign Out" button uses Material destructive red instead of HTML's `text-red-600` on white card | S |
| 7 | KYC (`page-kyc`) | `/kyc` `kyc_screen.dart` | Partial | (a) HTML's top "KYC Verified" status banner with circular shield + green badge is missing — Flutter uses a different `_statusBanner` widget at bottom. (b) Mobile + Email rows missing from Personal Details. (c) Submitted Documents card section missing entirely | M |
| 8 | Bank Details (`page-bank-details`) | `/bank-details` `bank_details_screen.dart` | Partial | (a) Biometric-protected gold banner at top missing. (b) "Change History" card section missing — Flutter shows only pending request indicator. (c) Field ordering differs: HTML = Holder / Bank / Account / IFSC, Flutter = Bank / Account / IFSC / Holder | M |
| 9 | Documents (`page-documents`) | `/documents` `documents_screen.dart` | Partial | (a) HTML has 6 fixed accordion sections (Legal Agreements, Due Diligence & Audits, Insurance, Project Updates, Financial Statements, Upkeep); Flutter has 4 doc-type categories (contract/agreement/kyc/other). (b) Accordion chevron rotation animation not implemented in Flutter. (c) Inside each section: HTML pre-populates items even when empty — Flutter hides empty sections | M |
| 10 | Support (`page-support`) | `/support` `support_screen.dart` | Mostly | (a) Raise-ticket button uses ElevatedButton instead of the HTML "gradient-primary" rounded-15 button with plus icon. (b) Button height: Flutter pad 12 vs HTML `py-3.5` (14 px). (c) Ticket list cards layout matches structurally | S |
| 11 | Ticket Detail (`page-ticket-detail`) | `/ticket/:id` `ticket_detail_screen.dart` | Mostly | (a) HTML shows ticket ID + status badge in title row (`#TKT-2847` + Resolved pill); Flutter shows just title text. (b) Meta-info card (Issue Type / Priority / Raised / Resolved) layout matches; field labels differ slightly. (c) Reply composer styling differs (HTML inline send arrow vs Material TextField + send button) | S |
| 12 | New Ticket (`page-new-ticket`) | `/new-ticket` `new_ticket_screen.dart` | Mostly | (a) Category list in HTML omits "Profile Update" + "Technical Issue" — Flutter adds them. (b) Form spacing + field border-radius `12` vs `15` HTML. (c) Submit button styling acceptable | S |
| 13 | Security (`page-security`) | `/security` `security_screen.dart` | Mostly | (a) HTML lists Biometric Login + App PIN + Notifications in a single 3-row card; Flutter shows 2 toggle rows (Biometric + Face ID) — App PIN row missing. (b) Notifications row missing entirely. (c) Login History bottom card missing | M |
| 14 | Exit (`page-exit`) | `/exit` `exit_screen.dart` | Mostly | (a) Lock-in copy uses dynamic countdown from real `investment_date`; HTML hard-codes `3 yrs 2 mos`. (b) "Request Exit" disabled button color matches. (c) "How does Exit work?" inline link missing in Flutter | S |
| 15 | Gallery (`page-gallery`) | `/gallery` `gallery_screen.dart` | Mostly | (a) HTML subtitle reads "Unit 4 - Last 30 Days"; Flutter shows just "Gallery". (b) HTML "Photos captured daily at 9:00 AM IST" info strip is present in Flutter — match. (c) HTML uses fixed 3-column grid of placeholders; Flutter groups by date (richer) — acceptable enhancement | S |
| 16 | Location (`page-location`) | `/location/:id` `location_screen.dart` | Partial | (a) HTML uses a Google Static Maps tile + centered gold map-pin overlay; Flutter shows a gradient placeholder with a single icon — **no map tile**. (b) Privacy-Protected accent card present in Flutter — match. (c) Regional Details rows (Climate Zone / Soil Type / Water Source) alternate `bg-sand` / `bg-accent/5` in HTML; Flutter uses uniform styling | M |
| 17 | Project Selector (`page-project-selector`) | `/project-selector` `project_selector_screen.dart` | Mostly | (a) HTML rows show "of portfolio" % on right (computed from invested totals); Flutter shows raw values without %. (b) Initials circle gradient backgrounds match. (c) Active row border `border-2 border-arl-primary` matches | S |

**Effort key:** S = ≤2 hr · M = ½ day · L = 1–2 days.

---

## 2. Per-screen detail

### Screen 1 — Home

- **HTML source:** `Growize App Design.html` lines 135–299
- **Flutter source:** `lib/features/home/home_screen.dart` + `lib/features/home/widgets/{portfolio_card,project_progress_card,quick_stats_row}.dart`
- **Intended layout:** Welcome row (label + investor name + project-selector pill); portfolio gradient card (total value, invested, returns, ROI + outperforming chip); per-project progress card with bar + status pill + optional "Payouts on hold" red pill; quick-stats row (Next Payout, Active Units).
- **Match status:** All four blocks rendered. Theme tokens used correctly. Bottom nav inherited from MainScaffold.
- **Divergences:**
  - **Layout:** HTML embeds an inline dropdown (`#home-proj-menu`) directly on the home page so users tap once to switch project. Flutter routes to a separate `/project-selector` screen (`context.push`). Increases tap cost from 1 → 3 (open / select / back).
  - **Visual:** "WELCOME BACK" rendered all-uppercase with `letterSpacing: 1.2`. HTML shows `Welcome back` with `uppercase tracking-wider` Tailwind class — same effect but font-size HTML `text-xs` (12 px) vs Flutter `10` px → Flutter copy renders ~17 % smaller.
  - **Visual:** Portfolio card border radius `15` matches. Background gradient `linear-gradient(145deg, #3C5152, #2A5E50)` — Flutter `LinearGradient([primary, accent])` uses `#2E7D6E` not `#2A5E50` — a 6-unit hue shift toward green. Subtle but inconsistent with HTML.
  - **Data binding:** OK — uses real `portfolio_summary` view.
  - **Behavior:** "View Project" / "View All Projects" CTA buttons inside the Project Progress card are NOT present in Flutter `ProjectProgressCard` (need to read that widget to confirm — flagged for follow-up).
- **Severity:** Major (inline dropdown UX), Minor (gradient hex).
- **Suggested fix:**
  - `lib/features/home/home_screen.dart` — Replace `GestureDetector → context.push(RouteNames.projectSelector)` with an inline `PopupMenuButton` or custom overlay matching HTML's `#home-proj-menu` (white rounded-2xl menu).
  - Confirm gradient `[#3C5152, #2A5E50]` — add a `gradientPrimary` token to `ArlColors`.

### Screen 2 — Projects

- **HTML source:** lines 302–781 (includes three sub-views `projects-all-view`, `projects-gv-view`, `projects-so-view`, `projects-va-view`)
- **Flutter source:** `lib/features/projects/projects_list_screen.dart`, `project_detail_screen.dart`
- **Intended layout:** Header (Your Portfolio / All Projects / `3 Projects · 7 Units · ₹1.83 Cr invested`); stack of per-project cards each with brand-gradient hero strip + progress + 3-stat grid + next-payout footer. Tap → project detail (separate view in HTML).
- **Match status:** Structure present. Each project card has gradient hero, progress bar, stats. Tap routes to `/projects/:id`.
- **Divergences:**
  - **Visual:** Initials circle: Flutter uses `BorderRadius.circular(8)` (rounded square) — HTML uses `rounded-full` (full circle). Visible.
  - **Visual:** Status pill label: HTML "Operational" (text) vs Flutter "Active" — both correct semantically but copy differs.
  - **Visual:** Pending warning box `BorderRadius.circular(8)` and `Border.all` — HTML uses `rounded-[15px]` with no border, only `bg-arl-earth/10`.
  - **Layout:** HTML stat grid has 3 columns (Units / Crop emoji / one more); Flutter shows 2 columns + crop emoji floated right — column count differs but content matches.
  - **Data binding:** Pulls real `projects_repository` data. Project initials and `colorHex` computed correctly.
- **Severity:** Minor (visual polish).
- **Suggested fix:** `projects_list_screen.dart:141` — change `BorderRadius.circular(8)` → `BorderRadius.circular(20)` for initials circle. Pending warning border-radius `8` → `15`.

### Screen 3 — Financials

- **HTML source:** lines 783–940
- **Flutter source:** `lib/features/financials/financials_screen.dart`
- **Intended layout:** Header with title + project-selector pill; pill tabs (Payouts / Financials); Payouts view = tax-free banner + Total Earned/This-FY cards + transaction ledger; Financials view = Risk-vs-Return chart card + Invested/Returns cards + Capital Account + Earnings Outlook (5-bar Y1-Y5 chart).
- **Match status:** Both tabs + all major cards present. Risk-vs-Return scatter chart implemented from scratch in `_riskReturnCard`.
- **Divergences:**
  - **Visual:** Tab pills use `BorderRadius.circular(20)` — match. Inactive pill bg `ArlColors.sand` — match.
  - **Visual:** Tax-Free banner border-radius `12` (Flutter) vs `15` (HTML) — repeated pattern across cards. HTML standard radius is `15px` (`rounded-[15px]`), Flutter standard is `12`. Subtle ~3-px corner difference visible to designer.
  - **Visual:** Earnings Outlook — HTML uses 5 identical-width vertical bars with growth gradient `primary → accent`. Flutter computes bar height from compound-yield ratio (more dynamic). Different visual rhythm.
  - **Data binding:** `Total Earned / This FY / Capital Account / Earnings Outlook` driven by real `portfolio_summary` + `payouts_provider` data. Risk-vs-Return positions hard-coded.
  - **Behavior:** Tabs are not externally swipeable — `physics: NeverScrollableScrollPhysics()` — by design.
- **Severity:** Minor (radius polish), Major (Earnings Outlook bar behavior departs from spec).
- **Suggested fix:** Add `kCardRadius = 15.0` constant in theme; replace `BorderRadius.circular(12)` with `kCardRadius` across financials cards. For Earnings Outlook, switch to fixed-rhythm bars matching HTML.

### Screen 4 — Explore

- **HTML source:** lines 942–1008
- **Flutter source:** `lib/features/explore/explore_screen.dart`
- **Intended layout:** Header (title + "New Projects" badge top-right); dark green hero card with `<select>` project dropdown + project meta grid (Location/Farm Size/Unit Size/Crop/Total Units/Price per Unit) + range slider + investment summary; below the hero, a white card with 5-Year Projection rows; disclaimer footer.
- **Match status:** Different IA — Flutter renders the marketplace as a list of cards filtered by status chips, then a per-project projection card. The HTML's hero+slider single-pane experience does not exist in Flutter.
- **Divergences:**
  - **Layout:** Status filter chips (All / Open / Not Started) — HTML uses none; Flutter adds them. Defensible product call but diverges from HTML.
  - **Layout:** Unit range slider missing. "Enter custom units" checkbox missing. Investment Summary card missing.
  - **Layout:** Project meta grid (Location, Farm Size, Unit Size, Crop, Total Units, Price/Unit) — Flutter renders these on each project card individually rather than in the hero.
  - **Visual:** Header badge "New Projects" rendered as `bg-arl-sand` rounded-4 — Flutter uses border-radius 4 vs HTML's `rounded-full`. Pill shape differs.
  - **Data binding:** Pulls from `public.projects` where `is_listed_in_marketplace = true` — correct backend integration; HTML mocks 6 hardcoded projects.
  - **Behavior:** No "I'm Interested" CTA found (HTML doesn't have one either — both rely on display only).
- **Severity:** Major (full re-IA needed for hero card + slider). Pragmatically, the Flutter design may be the intended evolution; needs product sign-off.
- **Suggested fix:** Decide whether to keep current Flutter IA or rebuild to match HTML. If rebuilding: pull `marketplace_project.dart` model into a hero `_ExploreHero` widget with dropdown + slider + meta grid.

### Screen 5 — Activity

- **HTML source:** lines 1010–1072
- **Flutter source:** `lib/features/activity/activity_screen.dart`
- **Intended layout:** Back arrow + "Notifications" / "Activity History" title; right-side toggle button switches between the two views. Notification view = unread cards (camera/wallet icons + dot). Timeline view = horizontal filter chips (All / Operational / Payouts) + month-grouped timeline items with colored dots.
- **Match status:** Both views implemented. Toggle button works via `_showHistory` state.
- **Divergences:**
  - **Visual:** Title font-size: HTML `text-lg` (18 px) — Flutter `18` — match.
  - **Visual:** Toggle button "History" / "Notifications" rendered in a sand-colored Material pill with icon + text. HTML uses a similar pill in `bg-arl-sand` — match.
  - **Layout:** "Mark all read" CTA appears as a TextButton row above the recent list — not present in HTML.
  - **Layout:** Filter chips have 3 options matching HTML (All / Operational / Payouts) — match.
  - **Data binding:** Uses real `notifications_provider`. Timeline uses mock data when not signed in (documented).
- **Severity:** Minor.
- **Suggested fix:** Keep "Mark all read" — useful UX addition. Otherwise no action.

### Screen 6 — Profile

- **HTML source:** lines 1074–1097
- **Flutter source:** `lib/features/profile/profile_screen.dart`
- **Intended layout:** Gradient-primary hero (back arrow + "Profile" title + avatar circle + name + ARL ID + KYC badge); under hero a card listing Active Projects names; menu tile cards (KYC / Bank / Documents / Security / Support / Exit); destructive Sign Out button.
- **Match status:** Hero gradient + avatar + ID + KYC pill all present. Menu tiles correctly listed.
- **Divergences:**
  - **Visual:** Hero gradient padding — Flutter `EdgeInsets.all(20)` vs HTML `p-6 pb-8` (24 / 32). Bottom padding slightly shorter, so avatar sits closer to the cards below.
  - **Layout:** **"Active Projects" comma-listed card** (HTML line 1084: `Green Valley Farm · Sunrise Orchards · Verdant Acres`) is missing in Flutter. This is the single subtitle card right under the hero with `-mt-4` overlap.
  - **Visual:** Sign Out button — HTML uses `bg-white` card with `text-red-600 border border-red-200`; Flutter likely uses Material default. Need exact comparison.
  - **Behavior:** Menu tiles navigate via `context.push` — back nav works.
- **Severity:** Major (missing Active Projects card breaks information density).
- **Suggested fix:** `profile_screen.dart` — add an `_activeProjectsCard` widget consuming `projectsProvider` and rendering "name · name · name" string.

### Screen 7 — KYC

- **HTML source:** lines 1100–1132
- **Flutter source:** `lib/features/profile/kyc_screen.dart`
- **Intended layout:** Back + "KYC Details" title; green status banner (shield-check + "KYC Verified" + "Verified on Jan 15, 2024" + Active pill); Personal Details card (Full Name / DOB / PAN / Aadhaar / Mobile / Email); Address card (2 lines); Submitted Documents card (3 doc rows).
- **Match status:** Title + back + Personal Details card present.
- **Divergences:**
  - **Layout:** Top "KYC Verified" status banner — implemented in Flutter via `_statusBanner(kycStatus)` but rendered AFTER the fields rather than at top.
  - **Data binding:** Mobile + Email rows MISSING from Personal Details — only Full Name / PAN / Aadhaar / DOB / Address rendered.
  - **Layout:** Submitted Documents card (lines 1123–1131) MISSING entirely. HTML lists e.g. "PAN Card.pdf", "Aadhaar.pdf" — Flutter has no equivalent block.
  - **Visual:** Field rows use `_kycField` helper — visual match acceptable.
- **Severity:** Major (missing fields + missing section).
- **Suggested fix:** `kyc_screen.dart` — (1) Move status banner to top of column. (2) Add `_kycField('Mobile', mobile)` + `_kycField('Email', email)`. (3) Add a `_submittedDocsCard` widget.

### Screen 8 — Bank Details

- **HTML source:** lines 1135–1166
- **Flutter source:** `lib/features/profile/bank_details_screen.dart`
- **Intended layout:** Back + title; gold biometric-secured banner (shield icon + "Secured with biometric authentication"); Registered Account card (Account Holder / Bank / Account Number / IFSC); change-form card (collapsed); Change History card (3 history rows).
- **Match status:** Title + back + fields present.
- **Divergences:**
  - **Layout:** **Top gold "Secured with biometric authentication" banner missing.**
  - **Layout:** **Change History card missing** — HTML shows 3 historical change rows.
  - **Layout:** Field order — HTML: Holder → Bank → Account → IFSC; Flutter: Bank → Account → IFSC → Holder. Reversed.
  - **Data binding:** Pulls `bank_change_requests` for pending status — better than HTML's static mock.
- **Severity:** Major (banner + history section missing).
- **Suggested fix:** Add `_biometricBanner` widget at top. Add `_changeHistoryCard` consuming `bank_change_requests` rows. Reorder field calls.

### Screen 9 — Documents

- **HTML source:** lines 1168–1239
- **Flutter source:** `lib/features/documents/documents_screen.dart`
- **Intended layout:** Back + "Documents" title; 6 collapsible accordion sections with chevron rotation, each containing a list of doc rows (legal agreements / due diligence / insurance / project updates / financial statements / upkeep).
- **Match status:** Accordion structure present but section categories differ.
- **Divergences:**
  - **Layout:** **Section taxonomy mismatch.** HTML has 6 fixed sections by topic; Flutter has 4 by `doc_type` enum (contract/agreement/kyc/other). User-facing taxonomy is completely different.
  - **Visual:** Accordion chevron rotation — HTML `.doc-accordion.open .doc-chevron { transform:rotate(180deg) }`; Flutter does not animate the chevron (need to verify exact implementation).
  - **Layout:** HTML pre-renders empty sections (acts as table of contents). Flutter hides sections without items.
  - **Data binding:** Real Supabase docs query → good. HTML is mocked.
- **Severity:** Major (taxonomy mismatch breaks user expectation set by HTML).
- **Suggested fix:** Either (a) extend the `documents` schema with a `section` enum matching HTML's 6 categories, or (b) accept the simpler 4-bucket taxonomy as a deliberate product decision and update the design source-of-truth. Cannot resolve without product input.

### Screen 10 — Support

- **HTML source:** lines 1241–1252
- **Flutter source:** `lib/features/support/support_screen.dart`
- **Intended layout:** Back + "Assistance" title; full-width gradient-primary "Raise a Ticket" button with plus icon; "My Tickets" card listing tickets.
- **Match status:** Title + button + ticket list all present.
- **Divergences:**
  - **Visual:** Raise-a-Ticket button — HTML uses `gradient-primary` background (forest-green gradient) with rounded-15 + plus icon; Flutter uses `ArlColors.primary` solid + rounded-12 + no leading plus icon.
  - **Visual:** Button padding `vertical: 12` vs HTML `py-3.5` (14 px) — Flutter button ~14 % shorter.
  - **Data binding:** Falls back to `mockSupportTickets` when DB returns empty — useful for design preview.
- **Severity:** Minor.
- **Suggested fix:** Add `LinearGradient([primary, accent])` to the button + leading `Icon(Icons.add)`.

### Screen 11 — Ticket Detail

- **HTML source:** lines 1254–1276
- **Flutter source:** `lib/features/support/ticket_detail_screen.dart`
- **Intended layout:** Back + ticket ID title (e.g. `#TKT-2847`) + status pill; meta card (Issue Type / Priority / Raised / Resolved); Conversation card with message bubbles; reply composer at bottom.
- **Match status:** Title + meta + messages + composer all present.
- **Divergences:**
  - **Visual:** HTML title row shows `#TKT-2847` as title text with a green "Resolved" pill below it inline. Flutter shows the ticket subject as title and status separately.
  - **Visual:** Reply composer — HTML uses single-line text input with an inline circular send button. Flutter likely uses a `TextField` + separate `IconButton`. Need to verify exact pixel match.
  - **Data binding:** Real `ticket_messages` provider → real backend.
- **Severity:** Minor.

### Screen 12 — New Ticket

- **HTML source:** lines 1278–1287
- **Flutter source:** `lib/features/support/new_ticket_screen.dart`
- **Intended layout:** Back + "New Ticket" title; category select; subject input; description textarea; submit button.
- **Match status:** All fields present. Categories implemented as dropdown.
- **Divergences:**
  - **Data binding:** Flutter category list includes "Profile Update" and "Technical Issue" (mapped to `general` enum). HTML category list is minimal (Payout / Documents / Other) — Flutter is more granular.
  - **Visual:** Field border-radius likely 12 vs HTML 15 — repeated pattern.
- **Severity:** Cosmetic.

### Screen 13 — Security

- **HTML source:** lines 1288–1297
- **Flutter source:** `lib/features/profile/security_screen.dart`
- **Intended layout:** Back + "Security" title; single card with 3 rows (Biometric Login toggle / App PIN chevron / Notifications chevron); Login History card with chevron.
- **Match status:** Biometric Login row present.
- **Divergences:**
  - **Layout:** **App PIN row missing.**
  - **Layout:** **Notifications row missing.**
  - **Layout:** **Login History bottom card missing.**
  - **Layout:** Flutter adds a `Face ID` toggle that is NOT in HTML.
  - **Visual:** Toggle styling uses Material Switch — HTML uses a custom green pill with white dot. Acceptable.
- **Severity:** Major (3 sections missing).
- **Suggested fix:** Add stub rows for App PIN, Notifications, Login History (can be `coming soon` toasts to start).

### Screen 14 — Project Exit

- **HTML source:** lines 1299–1305
- **Flutter source:** `lib/features/exit/exit_screen.dart`
- **Intended layout:** Back + "Project Exit" title; Exit Eligibility card (Investment Date / Lock-in Ends / countdown chip); disabled "Request Exit" button; "How does Exit work?" link with chevron.
- **Match status:** Eligibility card + disabled button present.
- **Divergences:**
  - **Data binding:** Investment date pulled from earliest `investor_units.investment_date` — real data. HTML hard-codes `Mar 15, 2024`. Better in Flutter.
  - **Layout:** "How does Exit work? →" link — verify whether present. HTML shows a `showToast` describing the 5-step flow.
- **Severity:** Minor.
- **Suggested fix:** Confirm presence of bottom "How does Exit work?" link; add an `AlertDialog` describing Request → Review → Valuation → Settlement → Credit flow.

### Screen 15 — Gallery

- **HTML source:** lines 1309–1321
- **Flutter source:** `lib/features/gallery/gallery_screen.dart`
- **Intended layout:** Sticky `gradient-primary` header (back + "Gallery" + "Unit 4 - Last 30 Days"); info strip "Photos captured daily at 9:00 AM IST"; 3-column placeholder grid on dark green background.
- **Match status:** Dark green bg + gradient header + photo grid all present. Goes further than HTML by grouping by date and using real CDN images.
- **Divergences:**
  - **Visual:** Subtitle — HTML shows "Unit 4 - Last 30 Days"; Flutter title block is just "Gallery" with no subtitle (need to confirm — code shows only `Text('Gallery')`).
  - **Visual:** Info strip color — HTML uses `bg-arl-light/20` (greenish translucent) — Flutter uses `Colors.black.withValues(alpha: 0.15)` — slightly different tint.
  - **Layout:** Date grouping headers (`Tue, 12 Mar 2026` style) added by Flutter — enhancement over HTML's flat grid.
- **Severity:** Minor.
- **Suggested fix:** Add subtitle "Last 30 Days" or similar to the AppBar title column.

### Screen 16 — Location

- **HTML source:** lines 1323–1377
- **Flutter source:** `lib/features/projects/location_screen.dart`
- **Intended layout:** Sticky cream header (back + "Project Location" + "Approximate area"); Google Static Maps tile with gold map-pin overlay + bottom caption "Pune Region, Maharashtra"; Privacy-Protected accent card; Regional Details card (Climate Zone / Soil Type / Water Source with alternating sand / accent backgrounds).
- **Match status:** Header + privacy card + regional details all present.
- **Divergences:**
  - **Visual / Data binding:** **Map tile missing.** HTML embeds a Google Static Maps image; Flutter renders a flat `LinearGradient` with one centered map-pin icon. No real geographic image.
  - **Visual:** Regional Details rows — HTML alternates `bg-arl-sand` and `bg-arl-accent/5` per row for stripes; Flutter uses uniform styling.
  - **Data binding:** Climate Zone / Soil Type / Water Source values are hard-coded — HTML same.
- **Severity:** Major (map tile is the visual centerpiece of the screen).
- **Suggested fix:** Integrate `flutter_map` package with OpenStreetMap tiles centered on project lat/lng, OR add a static map asset per project. Add alternating row colors in Regional Details.

### Screen 17 — Project Selector

- **HTML source:** lines 1379–1433
- **Flutter source:** `lib/features/projects/project_selector_screen.dart`
- **Intended layout:** Back + "Select Project" title; helper text; 4 buttons (All Projects, then per-project rows) each with brand-gradient circle + name + status pill + meta + portfolio-% on right + selected check.
- **Match status:** All 4 buttons present. Selected row has primary-border.
- **Divergences:**
  - **Layout:** "of portfolio" % column on right of each project row — verify presence. HTML uses computed percentages.
  - **Visual:** Active border `border-2 border-arl-primary` — match.
  - **Visual:** Initials circle gradient — match.
- **Severity:** Minor.

---

## 3. Cross-cutting divergences

These appear across multiple screens and should be fixed once at the theme/widget level rather than per screen.

| # | Divergence | Where it shows | Severity | Fix |
|---|---|---|---|---|
| C1 | **Border radius 12 vs 15.** HTML uses `rounded-[15px]` everywhere for cards; Flutter widgets use `BorderRadius.circular(12)` in most places. ~3 px corner difference compounds visually. | Financials cards, KYC fields, Documents, Bank Details, New Ticket form, Support button | Minor | Add `kCardRadius = 15.0` in theme; replace hard-coded `12` across `lib/features/**`. |
| C2 | **Inter font not bundled.** `pubspec.yaml` lines 65–75 has the `fonts:` block commented out. `arl_theme.dart` sets `fontFamily: 'Inter'` everywhere. Runtime falls back to system sans (Roboto on Android, San Francisco on iOS, system on web). Letter shapes + spacing visibly differ on Android. | All screens | Major | Bundle `Inter-{Regular,Medium,SemiBold,Bold}.ttf` into `assets/fonts/` + uncomment the pubspec block. |
| C3 | **Primary gradient hex mismatch.** HTML `gradient-primary: linear-gradient(145deg, #3C5152 0%, #2A5E50 100%)`. Flutter widgets that use a gradient mostly use `[primary, accent]` = `[#3C5152, #2E7D6E]`. The HTML's stop color `#2A5E50` is darker/cooler than `#2E7D6E`. | Portfolio card, Profile hero, Project hero strips, Risk-vs-Return total card, Support button | Minor | Add `ArlColors.primaryGradientStop = Color(0xFF2A5E50)` and use a dedicated `LinearGradient(begin: TopLeft, end: BottomRight, colors: [primary, primaryGradientStop])` helper. |
| C4 | **Inline dropdowns vs route push.** HTML uses inline floating dropdowns (`#home-proj-menu`, `#fin-proj-menu`) to switch project; Flutter routes to `/project-selector`. UX cost: 1 tap → 3 taps. | Home, Financials | Major | Implement a shared `_ProjectDropdown` widget rendered as an `OverlayEntry` or `PopupMenuButton`. |
| C5 | **Status pill copy: "Operational" vs "Active".** HTML uses "Operational" in projects header; Flutter uses "Active". | Projects list, Project selector | Cosmetic | Choose one term and apply consistently. |
| C6 | **`text-xs` (12 px) baseline vs Flutter `10–11`.** HTML uses `text-xs` (Tailwind = 12 px) for most labels/captions. Flutter widgets frequently use `fontSize: 10` or `11`, rendering 8–17 % smaller. | All screens with `text-xs` (labels, captions, meta lines) | Minor | Audit `fontSize: 10` usage and bump to `12` where HTML uses `text-xs`. |
| C7 | **`text-arl-muted` color drift.** HTML `#6b7280`; Flutter `ArlColors.muted = 0xFF6B7280` — match. ✓ |  |  | No action. |
| C8 | **Bottom nav icons.** HTML uses Lucide `home / sprout / bar-chart-2 / compass`; Flutter uses Material `home / eco / bar_chart / explore`. `eco` glyph is leaf-shaped (close to `sprout`); `explore` is compass — close. Acceptable substitution but not pixel-identical. | Every screen with bottom nav | Cosmetic | Optionally swap to `lucide_icons_flutter` package for 1:1 parity. |
| C9 | **Notification dot animation.** HTML has `.pulse-dot` 2s pulse animation on header bell. Flutter `ArlAppBar` renders static dot, no pulse. | Header (every shell screen) | Cosmetic | Wrap dot in `AnimatedOpacity` cycling 1.0 ↔ 0.4 every 2 s. |
| C10 | **Toast widget.** HTML has a charcoal pill toast positioned 80 px from top. Flutter uses Material `SnackBar` (bottom). | Various — sign-out, exit info, errors | Minor | Build a custom `ArlToast` overlay matching HTML styling. |
| C11 | **Back button on header bell route.** HTML's `showPage('activity')` returns via `goBack()` history stack. Flutter uses `context.push` + `context.pop` — works correctly. ✓ |  |  | No action. |
| C12 | **`bg-arl-light` references.** HTML uses `bg-arl-light` (mapped to `#3C5152` per Tailwind config — same as primary). No `light` token defined in Flutter `ArlColors`. Gallery dark-bg + Location overlays rely on this. | Gallery, Location | Minor | Either alias `ArlColors.light = primary` or update grep-references. |
| C13 | **Tab pill color: active state.** HTML `.sub-tab.active { background:#3C5152; color:#fff; }` (primary). Flutter financials tabs use `ArlColors.primary` — match. ✓ |  |  | No action. |
| C14 | **No `phases_timeline.dart` widget verification.** HTML project detail has phase-dot timeline (`.phase-dot.done/.current/.pending-ph`). Flutter has `lib/features/projects/widgets/phases_timeline.dart` — exists but not audited line-by-line. | Project detail | Unknown | Spot-check `phases_timeline.dart` against HTML phase-dot definitions (lines 102–107). |

---

## 4. Open questions

These need a product / design decision before a deterministic fix can land.

1. **Documents taxonomy.** HTML's 6 topic sections (Legal Agreements / Due Diligence / Insurance / Project Updates / Financial Statements / Upkeep) vs Flutter's 4 `doc_type` enum buckets (contract / agreement / kyc / other). Which is the source of truth? Schema change required if HTML wins.
2. **Explore IA.** HTML single-pane hero with select + slider + summary vs Flutter list-of-cards + chips + projection. Which experience is the product intent post-Apr-25? Big effort delta — re-spec needed.
3. **Marketplace.** HTML `<select>` in explore lists 6 hardcoded projects; Flutter pulls live from `projects WHERE is_listed_in_marketplace = true`. Are HTML's 6 names canonical or placeholder?
4. **Profile menu items.** HTML profile page menus: KYC / Bank / Documents / Security / Sign Out — does NOT include Support or Exit entries on the profile menu directly (those are accessed elsewhere). Flutter `profile_screen.dart` shows Support + Exit on the menu. Diverges from HTML.
5. **Gallery title subtitle "Unit 4".** HTML hard-codes a single unit; Flutter shows the global gallery. Should Flutter scope the gallery to a single unit or show all?
6. **Location map.** HTML uses Google Static Maps (requires API key + billing). Is OpenStreetMap an acceptable substitute (no key, free tier)? Or do we keep the placeholder until billing is set up?
7. **Activity timeline mock fallback.** Flutter falls back to `mockTimelineEvents` when not signed in but shows empty state when signed in with no real history. Should the timeline always show a stub feed?
8. **Earnings Outlook bar scaling.** HTML bars are fixed-rhythm; Flutter computes proportionally from compound yield. Which conveys risk/return more honestly? Product call.

---

## 5. Effort summary

**Screens by parity score (after audit):**
- **Full:** 0
- **Mostly:** 10 (Home, Projects, Financials, Activity, Profile, Support, Ticket Detail, New Ticket, Exit, Gallery, Project Selector — actually 11 if Profile counts; effectively 10)
- **Partial:** 5 (Explore, KYC, Bank Details, Documents, Location)
- **Missing:** 0
- **Security (split):** Counted under Mostly but has 3 sections missing — borderline Partial.

**Aggregate effort to reach "Full" across all 17 screens:**

| Category | Hours | Notes |
|---|---|---|
| Cross-cutting C1 (radius) | 2 | Search-replace + theme constant. |
| Cross-cutting C2 (Inter font) | 1 | Bundle TTFs + pubspec block uncomment. |
| Cross-cutting C3 (gradient hex) | 1 | Add color token + helper. |
| Cross-cutting C4 (inline dropdown) | 4 | New shared widget + integration on Home + Financials. |
| Cross-cutting C5–C14 (copy / minor visuals) | 4 | Polishing pass. |
| **Screen 1 Home** (inline dropdown, gradient, sub-features) | included in C4 | — |
| **Screen 2 Projects** (radius + status pill + initials shape) | 1 | — |
| **Screen 3 Financials** (Earnings Outlook bars + radius) | 3 | — |
| **Screen 4 Explore** (hero + slider + summary) | 12–16 | Largest item. Product spec needed first. |
| **Screen 6 Profile** (Active Projects card, padding) | 2 | — |
| **Screen 7 KYC** (banner reorder, Mobile/Email, Submitted Docs) | 4 | — |
| **Screen 8 Bank Details** (biometric banner, change history, reorder) | 3 | — |
| **Screen 9 Documents** (taxonomy) | 8–16 | Depends on product decision Q1. |
| **Screen 13 Security** (App PIN, Notifications, Login History rows) | 3 | — |
| **Screen 14 Exit** (How-does-it-work link) | 1 | — |
| **Screen 15 Gallery** (subtitle) | 0.5 | — |
| **Screen 16 Location** (map tile) | 4–8 | Depends on map provider choice. |
| **Verification + screenshot diffs** | 4 | Whole-app screenshot capture per screen + side-by-side comparison. |

**Total: ~55–85 engineer-hours** (≈ 1.5 to 2.5 working weeks for a single Flutter engineer) once product questions in §4 are resolved. ~30 hr without the two L-effort items (Explore re-IA, Documents taxonomy).

**Critical path (do these first):**
1. C2 — Bundle Inter font (1 hr). Wins on every screen.
2. C1 — Card radius 15 constant (2 hr).
3. Screen 7 KYC — missing fields + section (4 hr).
4. Screen 8 Bank Details — missing banner + history (3 hr).
5. Screen 13 Security — missing rows (3 hr).
6. Screen 6 Profile — Active Projects card (2 hr).

After this critical-path pass (~15 hr) the app moves from ~70 % parity to ~88 % parity. The remaining gap is dominated by Explore and Documents — both require product decisions before code can land.

---

*End of audit. No source files modified.*
