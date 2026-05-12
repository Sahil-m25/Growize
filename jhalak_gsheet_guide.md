# Jhalak — CP Outreach Google Sheet Guide

Last updated: 04 May 2026
Sheet: Growize_CP_Outreach_Jhalak_Updated
Sheet ID: 1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4

This is the complete reference for working with the CP Outreach tracker. It covers the daily workflow, escalation model, what each column does, and how to handle special situations.

---

## How the Sheet Works (Big Picture)

The sheet tracks every channel partner prospect through a multi-phase outreach journey. Each prospect starts at Track 2 (Cold outreach) and escalates through Track 3 (Warm referral) and Track 4 (Founder close) if they don't reply.

Each phase has its own dedicated date columns — escalating never clears data. When you complete an action, stamp today's date in the right column. The sheet formulas automatically compute your next action, when it is due, and whether it is overdue.

You only need to do these things:
1. Stamp today's date in the correct column after each action
2. Update dropdowns (Connect Accepted, Replied) when events happen
3. Change the Track dropdown when the formula says ESCALATE

Seven columns auto-update themselves: Current Stage (P), Stage Updated Date (Q), Days in Stage (R), Next Action (AO), Next Action Date (AP), Action Due (AQ), and Status (AR). Never edit these manually.

---

## The Escalation Model

Every prospect follows one path: **Cold → Warm → Founder**

```
Track 2 (Cold)  ──no reply──→  Track 3 (Warm)  ──no reply──→  Track 4 (Founder)
  Jhalak cold                    Jhalak + Pradeep               Pradeep personally
  Columns S-Y                    Columns Z-AB                   Columns AC-AE
```

Track 1 (Activation) is separate — it's for CPs who have already signed a mandate and need regular nudging from Pradeep.

At any point during any phase, if a prospect replies, the sequence stops and you handle it manually.

---

## Daily Workflow

Open the sheet each morning. Follow these steps:

**1. Filter for today's work**

Look at column AQ (Action Due?). You care about rows that start with:
- **TODAY** — action is due today
- **OVERDUE** — action was due earlier (shows how many days late and the original due date)

Sort or filter column AQ to bring OVERDUE and TODAY to the top. You can also sort by column AP (Next Action Date) to see everything in date order.

**2. Read your action list**

For each TODAY or OVERDUE row, read column AO (Next Action). Examples:
- "D1: Send LinkedIn connect (no note)" — go to LinkedIn and send a connect request
- "D5: Send Email 1" — send the first cold email
- "W1: Send warm referral email" — send a warm email mentioning Pradeep's recommendation
- "F1: Founder personal email (Pradeep sends)" — Pradeep needs to send this one
- "ESCALATE — Change Track to 3" — this prospect finished the cold phase, change Track dropdown to 3
- "ACTIVATION — Pradeep weekly nudge" — remind Pradeep to nudge this signed CP

**3. Do the action**

If the Cowork daily task has already drafted emails, check your Gmail Drafts folder. Review each draft, personalize if needed, and send. For LinkedIn actions, do them manually on LinkedIn.

**4. Stamp the date**

After completing an action, enter today's date in the correct column. Click the cell — a calendar date picker appears. The format is dd-MMM-yyyy (e.g. 04-May-2026).

**Cold phase stamps (Track 2):**

| Action you completed | Column to stamp |
|---------------------|-----------------|
| Sent LinkedIn connect request | **S** (Connect Sent) |
| LinkedIn connection was accepted | **T** (Connected Date) |
| Sent LinkedIn DM | **U** (First Message Date) |
| Sent first email | **V** (Email 1 Date) |
| Sent second email | **W** (Email 2 Date) |
| Did LinkedIn engagement | **X** (Follow-up Date) |
| Sent final cold nudge | **Y** (Final Nudge Date) |

**Warm phase stamps (Track 3):**

| Action you completed | Column to stamp |
|---------------------|-----------------|
| Sent warm referral email | **Z** (Warm Email 1) |
| Sent warm follow-up email | **AA** (Warm Follow-up) |
| Sent WhatsApp or made phone call | **AB** (Warm WA/Phone) |

**Founder phase stamps (Track 4):**

| Action you completed | Column to stamp |
|---------------------|-----------------|
| Pradeep sent personal email | **AC** (Founder Email 1) |
| Pradeep sent follow-up | **AD** (Founder Follow-up) |
| Pradeep sent final ask | **AE** (Founder Final Ask) |

**5. Handle escalation**

When column AO shows "ESCALATE — Change Track to 3" or "ESCALATE — Change Track to 4":
1. Go to column AI (Track) for that row
2. Change the dropdown from 2 to 3, or from 3 to 4
3. The formulas immediately show the first action of the new phase
4. Act on it (or it will show as due today)

You do NOT need to clear any columns. Cold dates stay in S-Y as history, warm dates stay in Z-AB.

**6. Update dropdowns as events happen**

- **AJ** (Connect Accepted?) — set to **Y** when accepted, **N** when rejected. Leave blank or Pending if not checked yet.
- **AK** (Replied?) — set to **Y** when any reply comes in on any channel. This halts the sequence.
- **AH** (Deal Stage) — update when conversion events happen: Call Booked, Call Done, Mandate Sent, Mandate Signed, Active.
- **AM** (Halt?) — set to **Y** to manually pause a prospect.

**7. Check for stale prospects**

Glance at column R (Days in Stage). Orange (6-10 days) or red (11+ days) means the prospect is going cold.

---

## The Four Tracks

### Track 1 — Activation (Signed CPs)

For channel partners who have already signed a mandate but have not yet started sending investor leads. The sheet flags "ACTIVATION — Pradeep weekly nudge" every day. Pradeep should nudge these CPs weekly.

### Track 2 — Cold Outreach (Starting Point)

All new prospects start here. Jhalak sends cold outreach via LinkedIn and email.

| Step | What to do | Stamp column | Spacing |
|------|-----------|-------------|---------|
| D1 | Send LinkedIn connect request (no note) | S | Due on Date Added |
| Wait | LinkedIn connect is pending — check back in 2 days | — | S + 2 days |
| Check | Has the connect been accepted? Update AJ | — | After 2 days |
| D3 | Send LinkedIn DM (only if accepted AND Email 1 not yet sent) | U | S + 2 days |
| D5 | Send Email 1 | V | U + 2 days (or S + 4 if LI rejected/timed out) |
| D8 | Send Email 2 | W | V + 3 days |
| D12 | Engage on their LinkedIn post | X | W + 4 days |
| D18 | Send final cold nudge | Y | X + 6 days |
| ESCALATE | Change Track to 3 | — | Due today |

Special behaviors:
- If LinkedIn is rejected (AJ = N), DM step is skipped — goes straight to Email 1
- If you skip a step, the formula advances gracefully
- Blank Connect Accepted is treated as Pending, not skipped
- After Y is filled, formula shows ESCALATE — change Track to 3 to start the warm phase

### Track 3 — Warm Referral (Escalation from Cold)

Jhalak sends warmer emails, mentioning Pradeep's recommendation. Only reaches this track after cold outreach is exhausted.

| Step | What to do | Stamp column | Spacing |
|------|-----------|-------------|---------|
| W1 | Send warm referral email (mention Pradeep) | Z | Due = date cold ended (Y) |
| W2 | Send warm follow-up email | AA | Z + 3 days |
| W3 | WhatsApp or phone nudge | AB | AA + 4 days |
| ESCALATE | Change Track to 4 | — | Due today |

Between steps, the sheet shows "Wait — warm follow-up pending".

### Track 4 — Founder Close (Escalation from Warm)

Pradeep sends personally. This is the final attempt. Only reaches this track after both cold and warm phases are exhausted.

| Step | What to do | Stamp column | Spacing |
|------|-----------|-------------|---------|
| F1 | Founder personal email (Pradeep sends) | AC | Due = date warm ended (AB) |
| F2 | Founder follow-up email | AD | AC + 6 days |
| F3 | Founder final ask | AE | AD + 7 days |
| END | SEQUENCE COMPLETE | — | — |

Between steps, the sheet shows "Awaiting founder action".

---

## Adding a New Lead

Fill in a row (between rows 3 and 200). The minimum fields required:

1. **A** (Prospect ID) — use the format CP-PROS-NNN (e.g. CP-PROS-015). This is the formula key.
2. **B** (Date Added) — today's date. Use the date picker.
3. **AI** (Track) — almost always **2** (Cold outreach). New prospects start cold.

Recommended additional fields:
- **C** (Full Name), **D** (Organization), **E** (Designation)
- **M** (LinkedIn URL) — important for Track 2
- **N** (Email) — required for email-based outreach

Once you fill A, B, and AI = 2, the formula columns auto-populate:
- P shows "Identified"
- AO shows "D1: Send LinkedIn connect (no note)"
- AP shows the due date (same as Date Added)
- AQ shows TODAY or OVERDUE
- AR shows "Action today" or "Overdue"

**When to use other tracks:**
- Track 1 — Only for CPs who have already signed a mandate (use Deal Stage dropdown too)
- Track 3/4 — Only via escalation from a lower track, never as starting point

---

## Understanding the Color Coding

### Row colors (entire row, columns A through AR)

| Row color | What it means | What to do |
|-----------|-------------|-----------|
| Dark gray | Halt = Y (prospect is parked) | Nothing — intentionally paused |
| Light gray | Replied = Y (prospect replied) | Handle manually — automation has stopped |
| Light red | Action overdue (AP date is past) | Act on this today — you are behind |
| Light green | Action due today (AP date is today) | Act on this today |
| Light gold | Track = 1 (Activation) | Pradeep should nudge this signed CP |

### Action Due colors (column AQ only)

| Cell color | Text style | Meaning |
|-----------|-----------|---------|
| Red background + dark red text | Bold | OVERDUE — action was due earlier |
| Green background + dark green text | Bold | TODAY — action is due today |
| Blue background + blue text | Normal | Future — action coming up soon |

### Days in Stage colors (column R only)

| Cell color | Days since last action | Meaning |
|-----------|----------------------|---------|
| Green | 0-2 days | Fresh — recently touched |
| Yellow | 3-5 days | OK — on schedule |
| Orange | 6-10 days | Cooling — needs attention soon |
| Red (with dark text) | 11+ days | STALE — this prospect is going cold |

---

## Understanding the Auto-Computed Columns

These seven columns are formula-driven. Do not type into them.

### P — Current Stage

Shows where the prospect is in the full escalation pipeline:

| Stage | What it means |
|-------|-------------|
| Signed | Deal Stage = Mandate Signed or Active |
| Mandate Sent | Deal Stage = Mandate Sent |
| Call Done | Deal Stage = Call Done |
| Call Booked | Deal Stage = Call Booked |
| Founder Final | Founder final ask sent (AE filled) |
| Founder Follow-up | Founder follow-up sent (AD filled) |
| Founder Contacted | Founder email sent (AC filled) |
| Warm Final | Warm WA/phone done (AB filled) |
| Warm Follow-up | Warm follow-up sent (AA filled) |
| Warm Contacted | Warm referral email sent (Z filled) |
| Replied | Prospect replied (AK = Y) |
| Cold Follow-up | Cold follow-up, engagement, or Email 2 done |
| Email Sent | First cold email sent (V filled) |
| DM Sent | LinkedIn DM sent (U filled) |
| Connected | LinkedIn connection accepted (T filled) |
| Connect Sent | LinkedIn connect request sent (S filled) |
| Identified | Prospect added, no actions taken yet |

### Q — Stage Updated Date

The date of the most recent action across all phases. Falls back to Date Added if no actions taken.

### R — Days in Stage

How many days since the last action. Color-coded for quick scanning.

### AO — Next Action

What to do next. Values include step instructions (like "D5: Send Email 1", "W1: Send warm referral email"), waiting states, escalation prompts ("ESCALATE — Change Track to 3"), and terminal states ("SEQUENCE COMPLETE", "PARKED", "REPLIED — handle manually").

### AP — Next Action Date

When the next action is due. For escalation rows, this is TODAY.

### AQ — Action Due?

Compares AP against today and shows context:
- **OVERDUE (5d) since 29-Apr** — the action was due 5 days ago on April 29
- **TODAY** — the action is due today
- **09-May (5d away)** — the action is due in 5 days on May 9
- **(blank)** — no action pending

### AR — Status

| Status | Meaning |
|--------|---------|
| Activation | Track 1, signed CP |
| Parked | Halted (AM = Y) |
| Replied | Got a reply, handle manually |
| Needs escalation | Phase complete, change Track |
| Action today | Something is due today |
| Overdue | Something was due earlier |
| Upcoming | Next action is in the future |
| In progress | Outreach started but nothing due yet |
| Not started | Has Prospect ID but no actions taken |
| Sequence complete | All phases finished |

---

## Handling Special Situations

### A prospect replies

1. Set AK (Replied?) to **Y**
2. Set AL (Reply Channel) to where they replied
3. The row turns light gray, AO changes to "REPLIED — handle manually"
4. Handle the conversation manually

### You want to pause a prospect

1. Set AM (Halt?) to **Y** — row turns dark gray, AO shows "PARKED"
2. To resume: change AM back to **N**

### Formula says ESCALATE

1. Read which track to change to (AO says "Change Track to 3" or "Change Track to 4")
2. Change column AI (Track) dropdown value
3. Formula immediately shows the first action of the new phase
4. Do not clear any date columns

### A prospect schedules a call

Update AH (Deal Stage) to "Call Booked". Progress through Call Done → Mandate Sent → Mandate Signed → Active as events happen. When signed, change Track to 1.

### LinkedIn connect is accepted later

Update AJ to **Y**. If Email 1 not yet sent, formula suggests DM first.

### LinkedIn connect is rejected

Set AJ to **N**. Formula skips DM, goes straight to Email 1.

### You skipped a step

Formulas handle this gracefully — they advance past skipped steps.

### The formulas look broken

Go to Extensions → Apps Script → Outreach → "Refresh formulas only".

---

## Column Quick Reference

### Columns you fill in when adding a lead

| Column | Letter | What to enter |
|--------|--------|--------------|
| Prospect ID | A | CP-PROS-NNN format |
| Date Added | B | Today's date |
| Full Name | C | Prospect's full name |
| Organization | D | Company / firm name |
| Designation | E | Job title |
| City | F | Location |
| LinkedIn URL | M | Full LinkedIn profile URL |
| Email | N | Email address |
| Phone | O | Phone number |
| Track | AI | Almost always **2** (Cold) |

### Dropdowns you update as events happen

| Column | Letter | Options | When to update |
|--------|--------|---------|---------------|
| Deal Stage | AH | None, Call Booked, Call Done, Mandate Sent, Mandate Signed, Active | When conversion events happen |
| Track | AI | 1, 2, 3, 4 | When formula shows ESCALATE |
| Connect Accepted? | AJ | Pending, Y, N | When LinkedIn request is accepted or rejected |
| Replied? | AK | Y, N | When any reply comes in |
| Reply Channel | AL | LinkedIn, Email, Phone, WhatsApp | When setting AK to Y |
| Halt? | AM | Y, N | When you want to pause or resume |

### Auto-computed columns (do not edit)

| Column | Letter | What it shows |
|--------|--------|-------------|
| Current Stage | P | Pipeline stage (full escalation pipeline) |
| Stage Updated Date | Q | Date of most recent action |
| Days in Stage | R | Days since last action (color-coded) |
| Stage Notes | AF | Manual notes field (you can type here) |
| Next Action | AO | What to do next |
| Next Action Date | AP | When the next action is due |
| Action Due? | AQ | TODAY, OVERDUE, FUTURE, or blank |
| Status | AR | Overall prospect status |

---

## Date Format

All date columns use **dd-MMM-yyyy** (e.g. 04-May-2026). Click a date cell for the calendar picker. The sheet enforces date validation — invalid entries are rejected.

---

## Using the Outreach Menu

**Run full setup** — Re-applies everything: headers, validations, formulas, and conditional formatting.

**Refresh formulas only** — Re-applies formulas in P, Q, R, AO, AP, AQ, AR.

**Pre-populate tracks** — Auto-assigns Track 1 for signed/active CPs, Track 2 for everyone else.

**Load test scenarios (trial only)** — Writes sample dates into rows 5-17 to test all tracks and escalation.
