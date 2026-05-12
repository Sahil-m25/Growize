# CP Outreach — Auto-Progression Formula Spec (v4.2)

Last updated: 04 May 2026
Script: `setup_outreach_formulas.gs` (v4.2)
Previous: v4.1 (cleanup + AQ formatting), v4 (escalation model), v3 (35/35 tests passed), v2 (action progression)

## What Changed in v4.2

Three structural additions on top of v4.1 to close real operator gaps:

1. **Tier column at G** — Was an unused `PROFILE_TIER` field in the script's CONFIG; now a dropdown (WM / Family Office / NRI Advisor / RE Advisor / Other) that the morning Cowork task reads directly. Replaces the previous "infer tier from designation/org each run" approach, which was inconsistent. No new column letter — repurposes existing G.

2. **Days In Track at AS** — A formula column distinct from R (Days in Stage). R counts days since the last action of any kind. AS counts days since the row entered its CURRENT track. Catches dead-air prospects per-track: a Track 2 row idle 14+ days is dying, escalate or archive. Track 1 always reads 0.

3. **Archived checkbox at AT** — Single-column flag. When TRUE: AO/AP/AQ blank, AR returns "Archived", row turns medium gray. Use for Won (after move to Track 1), Lost, or Dead-after-Track-4 prospects. Keeps the active view clean without deleting historical data.

## What Changed in v4

Tracks 2/3/4 are now **escalation stages** — a single prospect progresses Cold → Warm → Founder. Each phase has dedicated date columns so escalating never clears data.

| Track | Phase | Who sends | Columns | Terminal action |
|-------|-------|-----------|---------|-----------------|
| 1 | Activation | Pradeep nudges | — | (continuous) |
| 2 | Cold Outreach | Jhalak (cold) | S-Y | ESCALATE → Track 3 |
| 3 | Warm Referral | Jhalak (mentions Pradeep) | Z, AA, AB | ESCALATE → Track 4 |
| 4 | Founder Close | Pradeep (personally) | AC, AD, AE | SEQUENCE COMPLETE |

Conversion milestones (call, mandate) moved to AG (Call Date) + AH (Deal Stage dropdown).

## Column Map (row 2 = headers, data starts row 3)

| Col | Field | Type | Notes |
|-----|-------|------|-------|
| A | Prospect ID | text | Formula key — blank = skip row |
| B | Date Added | date | Used for D1 due date, fallback for Q |
| **G** | **Tier** | **dropdown** | WM / Family Office / NRI Advisor / RE Advisor / Other — drives email angle |
| **P** | **Current Stage** | **FORMULA** | Auto-derived — full escalation pipeline |
| **Q** | **Stage Updated Date** | **FORMULA** | MAX of all action dates, or Date Added |
| **R** | **Days in Stage** | **FORMULA** | TODAY - Q, with staleness colors |
| S | Connect Sent | date | Cold — Track 2 anchor |
| T | Connected Date | date | Cold — LI accepted |
| U | First Message Date | date | Cold — DM sent |
| V | Email 1 Date | date | Cold |
| W | Email 2 Date | date | Cold |
| X | Follow-up / Engagement | date | Cold |
| Y | Final Nudge Date | date | Cold — end of cold phase |
| Z | Warm Email 1 | date | Warm — referral intro (was Call Scheduled) |
| AA | Warm Follow-up | date | Warm — follow-up email (was Call Done) |
| AB | Warm WA/Phone | date | Warm — WhatsApp/phone nudge (was Call Outcome) |
| AC | Founder Email 1 | date | Founder — Pradeep personal (was Mandate Sent) |
| AD | Founder Follow-up | date | Founder — Pradeep follow-up (was Mandate Signed) |
| AE | Founder Final Ask | date | Founder — final attempt (was Founder For Call) |
| AF | **Stage Notes** | text, manual | Free-form notes |
| AG | Call/Meeting Date | date | Conversion — any phase (was Next Followup) |
| AH | Deal Stage | dropdown | Conversion tracking (was Notes) |
| AI | Track | dropdown 1-4 | 1=Activation, 2=Cold, 3=Warm, 4=Founder |
| AJ | Connect Accepted? | dropdown Pending/Y/N | Blank treated same as Pending |
| AK | Replied? | dropdown Y/N | Y halts sequence at any phase |
| AL | Reply Channel | dropdown | LinkedIn, Email, Phone, WhatsApp |
| AM | Halt? | dropdown Y/N | Y parks the row |
| AO | Next Action | **FORMULA** | Auto-computed; blank if archived |
| AP | Next Action Date | **FORMULA** | Auto-computed; blank if archived |
| AQ | Action Due? | **FORMULA** | TODAY / OVERDUE / FUTURE; blank if archived |
| AR | Status | **FORMULA** | Auto-computed; "Archived" wins over everything else |
| **AS** | **Days In Track** | **FORMULA** | Days since current Track was entered (v4.2) |
| **AT** | **Archived** | **checkbox** | TRUE hides row from active workflow (v4.2) |

## Auto-Stage Tracking

Jhalak stamps ONE date after acting. P, Q, R compute themselves.

### Current Stage (P) — full escalation pipeline

| Priority | Condition | Stage |
|----------|-----------|-------|
| 1 (highest) | AH = "Mandate Signed" or "Active" | Signed |
| 2 | AH = "Mandate Sent" | Mandate Sent |
| 3 | AH = "Call Done" | Call Done |
| 4 | AH = "Call Booked" | Call Booked |
| 5 | AE (Founder Final) filled | Founder Final |
| 6 | AD (Founder Follow-up) filled | Founder Follow-up |
| 7 | AC (Founder Email 1) filled | Founder Contacted |
| 8 | AB (Warm WA/Phone) filled | Warm Final |
| 9 | AA (Warm Follow-up) filled | Warm Follow-up |
| 10 | Z (Warm Email 1) filled | Warm Contacted |
| 11 | AK = Y | Replied |
| 12 | Y, X, or W filled | Cold Follow-up |
| 13 | V (Email 1) filled | Email Sent |
| 14 | U (First Message) filled | DM Sent |
| 15 | T (Connected) filled | Connected |
| 16 | S (Connect Sent) filled | Connect Sent |
| 17 (lowest) | Has ID, nothing stamped | Identified |

### Stage Updated Date (Q)

`MAX(S, T, U, V, W, X, Y, Z, AA, AB, AC, AD, AE, AG)` — the most recent action date.
Falls back to Date Added (B) if no actions have been taken yet.

### Days in Stage (R) — with staleness colors

`TODAY() - Q` — auto-counts days since last action.

| Days | Color | Label |
|------|-------|-------|
| 0-2 | Green (#d9ead3) | Fresh |
| 3-5 | Yellow (#fff2cc) | OK |
| 6-10 | Orange (#fce5cd) | Cooling |
| 11+ | Red (#f4cccc) | STALE |

### Days In Track (AS, v4.2) — track-aware staleness

Distinct from R. R counts days since *any* action; AS counts days the row has been in its *current* track. This catches dead-air per-track that R can't surface alone (e.g. a row that escalated to Track 3 12 days ago and has not moved).

Anchor logic by track:

| Track | Anchor | Notes |
|-------|--------|-------|
| 1 | always 0 | Continuous activation, not time-bounded |
| 2 (Cold) | MAX(S..Y, B) | Floor is Date Added |
| 3 (Warm) | MAX(Z, AA, AB), or Y if all blank, or B | Y = cold end is the entry point |
| 4 (Founder) | MAX(AC, AD, AE), or AB, or Y, or B | AB = warm end is the entry point |

Track-specific staleness colors on AS:

| Track | Warning (orange) | Stuck (red, bold) |
|-------|-----------------|-------------------|
| 2 | 10–14 days | > 14 days — escalate to 3 or archive |
| 3 | 7–10 days | > 10 days — escalate to 4 |
| 4 | 10–14 days | > 14 days — archive (sequence dead) |
| 1 | — | — |

Decision rule when AS goes red: escalate (raise Track) if the next phase exists, otherwise check AT (Archived) and move on.

---

## Track Sequences

### Track 1 — Activation (Signed CPs)

| Action | Trigger | Due |
|--------|---------|-----|
| ACTIVATION — Pradeep weekly nudge | Track = 1 | Always TODAY |

Surfaces every day until CP becomes Active.

### Track 2 — Cold Outreach (columns S through Y)

Jhalak sends cold. Ends with ESCALATE, not SEQUENCE COMPLETE.

| Step | Action | Trigger | Stamps | Due |
|------|--------|---------|--------|-----|
| D1 | Send LinkedIn connect (no note) | S empty | S | Date Added |
| — | Wait — LinkedIn connect pending | S filled, AJ blank or Pending, <2 days | — | S + 2 |
| — | Check LinkedIn — accepted? | S filled, AJ blank or Pending, >=2 days | — | TODAY |
| D3 | Send LinkedIn DM | AJ = Y, U empty, **V empty** | U | S + 2 |
| D5 | Send Email 1 | AJ = Y, U filled, V empty | V | U + 2 |
| D5-alt | Send Email 1 (LI not accepted) | AJ = N, V empty | V | S + 4 |
| D5-fb | Send Email 1 (fallback) | S filled 4+ days, V empty | V | S + 4 |
| D8 | Send Email 2 | V filled, W empty, V + 3 days | W | V + 3 |
| D12 | Engage on their LinkedIn post | W filled, X empty, W + 4 days | X | W + 4 |
| D18 | Send final nudge | X filled, Y empty, X + 6 days | Y | X + 6 |
| — | **ESCALATE — Change Track to 3** | Y filled | — | Y (cold end) |

**Key behaviors:**
- Blank Connect Accepted is treated as "Pending"
- DM step (D3) only fires if Email 1 (V) hasn't been sent yet
- If LI is rejected (AJ = N), skips DM and goes straight to Email 1
- When Y is filled, formula shows ESCALATE with due = TODAY

### Track 3 — Warm Referral (columns Z, AA, AB)

Jhalak sends, mentioning Pradeep's recommendation. Ends with ESCALATE.

| Step | Action | Trigger | Stamps | Due |
|------|--------|---------|--------|-----|
| W1 | Send warm referral email | Z empty | Z | Y (cold end) or B |
| W2 | Send warm follow-up email | Z filled, AA empty, Z + 3 days | AA | Z + 3 |
| W3 | WhatsApp / phone nudge | AA filled, AB empty, AA + 4 days | AB | AA + 4 |
| — | **ESCALATE — Change Track to 4** | AB filled | — | AB (warm end) |

Between steps shows "Wait — warm follow-up pending" (not yet time).

### Track 4 — Founder Close (columns AC, AD, AE)

Pradeep sends personally. True terminal state.

| Step | Action | Trigger | Stamps | Due |
|------|--------|---------|--------|-----|
| F1 | Founder personal email (Pradeep sends) | AC empty | AC | AB (warm end) or B |
| F2 | Founder follow-up email | AC filled, AD empty, AC + 6 days | AD | AC + 6 |
| F3 | Founder final ask | AD filled, AE empty, AD + 7 days | AE | AD + 7 |
| — | SEQUENCE COMPLETE | AE filled | — | — |

Between steps shows "Awaiting founder action" (not yet time).

---

## Escalation Flow

```
Track 2 (Cold) ──Y filled──→ ESCALATE ──Jhalak changes Track to 3──→
Track 3 (Warm) ──AB filled──→ ESCALATE ──Jhalak changes Track to 4──→
Track 4 (Founder) ──AE filled──→ SEQUENCE COMPLETE
```

**To escalate:** Jhalak changes the Track dropdown (AI) from 2→3 or 3→4. No columns need clearing — each phase has its own dedicated date columns. Cold dates stay in S-Y, warm dates in Z-AB, founder dates in AC-AE.

**First action anchors to previous phase end date.** Track 3 W1 is due on the date Y (cold final nudge) was stamped. Track 4 F1 is due on the date AB (warm WA/phone) was stamped. This means if Jhalak delays the escalation, AQ correctly shows OVERDUE with the number of days late. ESCALATE rows also anchor to the phase end date for the same reason.

## Priority Order (evaluated top to bottom in formulas)

1. No Prospect ID → blank
2. Track 1 → "ACTIVATION — Pradeep weekly nudge"
3. Halt = Y → "PARKED"
4. Replied = Y → "REPLIED — handle manually"
5. Track-specific sequence logic (2/3/4)

## Action Due (AQ) Values

AQ now shows context — how long overdue, or when future items are due.

| Format | Example | Meaning |
|--------|---------|---------|
| OVERDUE (Xd) since dd-MMM | OVERDUE (5d) since 29-Apr | Due date was 5 days ago |
| TODAY | TODAY | Due date = today |
| dd-MMM (Xd away) | 09-May (5d away) | Due in 5 days |
| (blank) | | No action pending (complete, parked, replied, or no data) |

Filtering tip: sort/filter on AQ — OVERDUE rows sort to top alphabetically. Or filter column AP (Next Action Date) directly for date-based sorting.

## Status (AR) Values

Archived takes top priority — once AT=TRUE the row reads "Archived" regardless of any other state.

| Value | Meaning |
|-------|---------|
| Archived | AT = TRUE (v4.2 — Won, Lost, or Dead-after-Track-4) |
| Activation | Track 1, signed CP |
| Parked | Halt = Y |
| Replied | Replied = Y, needs manual follow-up |
| Needs escalation | Track 2 or 3 complete, ready for next phase |
| Action today | AQ = TODAY |
| Overdue | AQ = OVERDUE |
| Upcoming | AQ = FUTURE |
| In progress | Has started (S, Z, or AC filled) but no action due yet |
| Not started | Has ID but nothing stamped |
| Sequence complete | All steps done (Track 4 AE filled) |

## Conditional Formatting

### Row-level (columns A-AT)

Rules evaluated top-down, first match wins. Archived deliberately precedes Halt/Replied so an archived row always reads as gray regardless of other state.

| Order | Color | Rule |
|-------|-------|------|
| 1 (highest) | Medium gray (#b7b7b7) + dim text | AT = TRUE (v4.2) |
| 2 | Dark gray (#cccccc) | Halt = Y |
| 3 | Light gray (#efefef) | Replied = Y |
| 4 | Light red (#f4cccc) | AP < TODAY (overdue action) |
| 5 | Light green (#d9ead3) | AP = TODAY (action due today) |
| 6 | Light gold (#fce5cd) | Track = 1 (Activation) |

### Action Due column (AQ only)

| Color | Condition | Text style |
|-------|-----------|------------|
| Red (#f4cccc) + dark red text | AP < TODAY | Bold |
| Green (#d9ead3) + dark green text | AP = TODAY | Bold |
| Blue (#cfe2f3) + blue text | AP > TODAY | Normal |

### Days in Stage (column R only)

| Color | Days | Meaning |
|-------|------|---------|
| Green (#d9ead3) | 0-2 | Fresh — recently touched |
| Yellow (#fff2cc) | 3-5 | OK — on schedule |
| Orange (#fce5cd) | 6-10 | Cooling — needs attention soon |
| Red (#f4cccc) + dark text | 11+ | STALE — overdue for action |

### Days In Track (column AS only, v4.2)

Track-aware. Same color but the threshold differs by track.

| Color | Track 2 | Track 3 | Track 4 | Meaning |
|-------|---------|---------|---------|---------|
| Orange (#fce5cd) | 10–14 | 7–10 | 10–14 | Approaching stuck |
| Red (#f4cccc) + bold | > 14 | > 10 | > 14 | Stuck — escalate or archive |

## Dropdown Validations

| Column | Options |
|--------|---------|
| G (Tier) | WM, Family Office, NRI Advisor, RE Advisor, Other (v4.2) |
| AI (Track) | 1, 2, 3, 4 |
| AH (Deal Stage) | None, Call Booked, Call Done, Mandate Sent, Mandate Signed, Active |
| AJ (Connect Accepted?) | Pending, Y, N |
| AK (Replied?) | Y, N |
| AL (Reply Channel) | LinkedIn, Email, Phone, WhatsApp |
| AM (Halt?) | Y, N |
| AT (Archived) | checkbox — TRUE / FALSE (v4.2) |

## Adding New Leads

Minimum fields to fill for auto-progression to work:

1. **A** — Prospect ID (e.g. CP-PROS-015)
2. **B** — Date Added
3. **G** — Tier (WM / Family Office / NRI Advisor / RE Advisor / Other) — *new in v4.2.* Required so the morning task picks the right email angle.
4. **AI** — Track (almost always **2** for new prospects)

Formulas pre-exist in rows 3-200. New leads in this range auto-calculate immediately.

For Track 2: Connect Accepted (AJ) can be left blank — formula treats blank as "Pending".

All new prospects start at Track 2 (Cold). Track 3/4 only via manual escalation.

If Tier (G) is blank, the morning task still runs but logs a "Tier missing" warning so you can backfill.

## Bugs Fixed

### v2 (action progression)

1. **Blank Connect Accepted silent skip** — blank AJ treated as Pending.
2. **DM regression after emails** — D3 only fires if V also empty.
3. **Activation rows invisible** — AQ = TODAY always for Track 1.
4. **Duplicate "Next Action" header** — AF renamed to "Stage Notes".

### v3 (stage tracking)

5. **P/Q/R were fully manual** — now formula-driven.
6. **No staleness visibility** — Days in Stage color-coded.
7. **Track 1 AP/AQ empty (nested-IF bug)** — moved inside SWITCH.
8. **D1 AP showing TODAY() instead of Date Added** — changed to use $B.
9. **No date validation** — added requireDate() to all action columns.
10. **Timezone offset in tests** — changed to local-timezone date constructor.

### v4 (escalation model)

11. **Tracks were parallel, not sequential** — Tracks 3/4 used same V/W/X/Y columns as Track 2, requiring column clearing on escalation. Now each phase has dedicated columns (S-Y, Z-AB, AC-AE). No data loss on escalation.
12. **Conversion columns repurposed** — Z/AA (Call Scheduled/Done) and AC/AD (Mandate Sent/Signed) repurposed for warm/founder phases. Conversion tracking moved to AG (Call Date) + AH (Deal Stage dropdown).

### v4.1 (data cleanup + formatting)

13. **Old text in repurposed columns** — AB (was Call Outcome) and AE (was Founder For Call) had leftover text data that poisoned `<>""` checks. Added `clearRepurposedColumns_()` to strip non-date values from Z-AE and AG-AH on setup.
14. **AQ day arithmetic produced decimals** — `TODAY()-$AP` could yield non-integer when concatenated. Wrapped in `INT()` for clean display.
15. **Conditional formatting broken by descriptive AQ** — Row-level rules used `$AQ="OVERDUE"` exact match which no longer works with "OVERDUE (5d) since 29-Apr". Changed to `$AP<TODAY()` date comparison.
16. **AQ column lacked visual distinction** — Added column-specific formatting: red+bold (overdue), green+bold (today), blue (future).

### v4.2 (Tier + stuck-row + archive)

17. **Tier inferred per-run, not stored** — The morning Cowork task was inferring prospect tier (WM/FO/NRI/RE) from designation/org each morning, producing inconsistent angles run to run. Repurposed unused column G as a Tier dropdown; morning task now reads it directly.
18. **No per-track staleness signal** — R (Days in Stage) counted any action; rows that escalated and then sat idle did not surface as stale because cold-phase actions still pulled MAX. Added AS (Days In Track) with track-specific thresholds and color coding.
19. **No archive flow** — Won, Lost, and Dead-after-Track-4 prospects stayed in the active view forever, polluting OVERDUE filters. Added AT (Archived) checkbox; AO/AP/AQ blank when checked, AR returns "Archived", row turns medium gray.
20. **doPost couldn't stamp Tier or Archived** — STAMP_COL_MAP gained G and AT entries; new CHECKBOX_COLS branch handles boolean values from external automations.

## Jhalak's Workflow (after v4.2)

After acting on an outreach step, Jhalak only needs to:

1. **Stamp the date** in the appropriate column:
   - Cold: S, T, U, V, W, X, or Y
   - Warm: Z, AA, or AB
   - Founder: AC, AD, or AE
2. **Update AJ** (Connect Accepted) when LinkedIn requests are accepted/rejected
3. **Update AK** (Replied) when any reply lands
4. **Change AI** (Track) when formula shows ESCALATE (2→3 or 3→4)
5. **Update AH** (Deal Stage) when call/mandate events happen
6. **Tick AT** (Archived) when a prospect is Won, Lost, or Dead-after-Track-4 (v4.2)
7. **Fill G** (Tier) at lead-add time (v4.2)

Everything else auto-updates: P, Q, R, AO, AP, AQ, AR, AS.

## Script Menu

After running setup, an "Outreach" menu appears in the sheet:

- **Run full setup** — Headers, validations, formulas, conditional formatting
- **Refresh formulas only** — Re-apply all formulas (P/Q/R + AO-AR) without touching other settings
- **Pre-populate tracks** — Signed/Active → Track 1, all others → Track 2 (skips rows with existing tracks)
- **Load test scenarios (trial only)** — Writes sample dates into rows 5-17 covering all tracks + escalation + edge cases

## Auto-Stamp Web Endpoint (doPost)

The script includes a web app endpoint for automated date stamping.

**Deploy:** Apps Script editor → Deploy → New deployment → Web app → Execute as Me, Anyone with link.

**Security:** Set a script property `STAMP_SECRET` (Project Settings → Script Properties).

**Request format:**
```json
{
  "secret": "<STAMP_SECRET value>",
  "updates": [
    { "prospectId": "CP-PROS-003", "column": "V", "value": "2026-05-04" },
    { "prospectId": "CP-PROS-007", "column": "AK", "value": "Y" }
  ]
}
```

**Allowed columns:**
- Dates: S, T, U, V, W, X, Y, Z, AA, AB, AC, AD, AE, AG
- Dropdowns: G (Tier), AH, AJ, AK, AL, AM
- Checkboxes: AT (Archived) — accepts true / false / "TRUE" / "FALSE"

**Response:** `{ "status": "ok", "applied": 2, "errors": [] }`

**Health check (GET):** Returns `{ "status": "ok", "sheet": "CP_Outreach", "prospects": N, ... }`
