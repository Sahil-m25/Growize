# Jhalak — Cowork Daily Outreach Setup Guide

Last updated: 04 May 2026
Version: 3.0 (with evening sync + auto-stamp)

This guide sets up two automated tasks in Jhalak's Claude Cowork that together handle the full daily outreach cycle for Growize CP acquisition.

---

## What This System Does

Two scheduled tasks run automatically, Monday through Saturday:

### Morning Task — `daily-cp-outreach` (9 AM)

| Step | What it does | Where | Tool used |
|------|-------------|-------|-----------|
| 1 | Reads the Google Sheet and filters for rows due today or overdue | Google Drive | Drive connector |
| 2 | Reads the Growize credibility doc for approved claims | Google Drive | Drive connector |
| 3 | Categorizes actions into email drafts, LinkedIn manual, and activation reminders | Internal | — |
| 4 | Researches each prospect (LinkedIn, org, recent news) | Web / LinkedIn | Sales plugin |
| 5 | Drafts personalized emails per track voice (Pradeep for Track 4, Jhalak for Track 2/3) | Internal | — |
| 5B | Rewrites every email to remove AI language and sound human | Internal | Marketing plugin |
| 6 | Saves each email as a Gmail draft (Jhalak reviews and sends manually) | Gmail | Gmail connector |
| 7 | Outputs a daily summary file with all drafts, LinkedIn actions, and activation reminders | File | — |

### Evening Task — `evening-outreach-sync` (6 PM)

| Step | What it does | Where | Tool used |
|------|-------------|-------|-----------|
| 1 | Reads the Google Sheet to build a prospect lookup | Google Drive | Drive connector |
| 2 | Scans Gmail Sent folder for emails Jhalak sent today, matches them to prospects | Gmail | Gmail connector |
| 3 | Scans Gmail for replies FROM prospect addresses in the last 24 hours | Gmail | Gmail connector |
| 4 | Determines which column to stamp for each sent email (V, W, X, or Y) | Internal | — |
| 5 | Auto-stamps dates in the sheet via the Apps Script endpoint OR generates a manual checklist | Google Sheet | Apps Script endpoint |

### What remains manual

| Action | Why it can't be automated |
|--------|--------------------------|
| Reviewing and sending Gmail drafts | Intentional — human review before sending |
| LinkedIn actions (connect, DM, engage) | LinkedIn blocks automation |
| Updating AJ (Connect Accepted?) | Requires checking LinkedIn manually |
| Stamping LinkedIn action dates (S, U) | Evening task can't detect LinkedIn actions — it reminds Jhalak instead |

---

## Prerequisites

Before starting, confirm:

- Jhalak has Claude Desktop installed with Cowork mode enabled
- Jhalak is signed in with her Anthropic account
- The Google Sheet "Growize_CP_Outreach_Jhalak_Updated" (sheet ID: `1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4`) has the v3 Apps Script applied (Outreach menu visible)
- Jhalak's Google account: `jhalak.wadhwa@agresearchlabs.com`

---

## Step 1: Connect Gmail

1. Open Claude Desktop and switch to Cowork mode
2. Go to Settings (gear icon) then Connectors
3. Search for **Gmail**
4. Click **Connect** and sign in with `jhalak.wadhwa@agresearchlabs.com`
5. Grant permissions: read, compose, modify drafts
6. Verify: ask Claude "list my Gmail labels" — if it responds with your labels, the connection works

## Step 2: Connect Google Drive

1. Same Settings then Connectors screen
2. Search for **Google Drive**
3. Click **Connect** and sign in with the same Google account
4. Grant read permissions
5. Verify: ask Claude "search my Drive for Growize_CP_Outreach" — it should find the sheet

## Step 3: Install Plugins

1. In Cowork, go to Settings then Plugins
2. Search for and install the **Sales** plugin — this provides `sales:draft-outreach` (prospect research + personalized email drafting) and `sales:account-research` (background research on organizations)
3. Search for and install the **Marketing** plugin — this provides `marketing:email-sequence` (multi-step outreach sequences) and `marketing:brand-review` (voice consistency checking)
4. Verify: ask Claude "list my skills" — you should see `sales:draft-outreach`, `sales:account-research`, `marketing:email-sequence`, and `marketing:brand-review` in the list

## Step 4: Create the Scheduled Task

In Cowork, type exactly:

> /schedule

When prompted, use these details:

- **Task name:** `daily-cp-outreach`
- **Schedule:** Every day at 9 AM except Sunday (cron: `0 9 * * 1-6`)
- **Prompt:** Copy-paste the entire prompt from the section below

---

## Scheduled Task Prompt

Copy everything between the START and END lines.

---START PROMPT---

You are running the daily CP outreach prep for Growize channel partner acquisition. Execute these steps in order. Do not skip steps. If any step fails, note the failure and continue to the next step.

STEP 1 — READ THE CP OUTREACH SHEET

Search Google Drive for the spreadsheet titled "Growize_CP_Outreach_Jhalak_Updated" (owned by jhalak.wadhwa@agresearchlabs.com, sheet ID: 1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4). Read the file content. Focus on the "CP_Outreach" tab.

Column map (row 2 = headers, data starts row 3):

| Col | Field | Purpose |
|-----|-------|---------|
| A | Prospect ID | Row key (e.g. CP-PROS-001). Blank = skip row |
| B | Date Added | When prospect was added |
| C | Full Name | Prospect name |
| D | Organization / Firm | Company name |
| E | Designation | Job title |
| F | City | Location |
| G | Tier | WM / Family Office / NRI Advisor / RE Advisor / Other — drives email angle |
| M | LinkedIn URL | Profile link for research |
| N | Email | Email address for outreach |
| AI | Track | 1=Activation, 2=Cold outreach, 3=Warm referral, 4=Founder close |
| AJ | Connect Accepted? | Pending / Y / N |
| AK | Replied? | Y / N |
| AM | Halt? | Y / N |
| AO | Next Action | Auto-computed by sheet formula |
| AP | Next Action Date | Auto-computed by sheet formula |
| AQ | Action Due? | TODAY / OVERDUE / FUTURE (auto-computed) |
| AR | Status | Auto-computed by sheet formula |
| AS | Days In Track | Auto-computed; flags stuck rows |
| AT | Archived | Checkbox; TRUE means skip entirely |

Filter for rows where column AQ starts with "TODAY" or starts with "OVERDUE". AQ now shows context like "OVERDUE (5d) since 29-Apr" — use this to prioritize the most overdue items first.

Skip any row where ANY of the following are true (this is the hard skip-list — never act on these rows):
- AT = TRUE (archived — Won, Lost, or Dead-after-Track-4)
- AM = "Y" (halted)
- AK = "Y" (already replied — handle manually, do not draft new emails)
- A is blank (no prospect ID)

These should already be filtered out by the sheet formulas (AO returns blank for archived rows), but double-check explicitly. Drafting an email to a prospect who already replied is the worst-case error mode of this system.

STEP 2 — READ THE CREDIBILITY DOC

Search Google Drive for a file containing "Growize" and "Credibility" or "Brand". Read its content. Extract credibility points such as: IIMB affiliation, partnerships (Blinkit, BigBasket, Samunnati), EBITDA-positive status, traction metrics, or any approved language.

If the doc is not found or is empty, note this as a blocker and draft emails conservatively without specific claims. Do not fabricate credibility points.

STEP 3 — CATEGORIZE ACTIONS

Group the filtered rows from Step 1 into three buckets:

A) EMAIL DRAFTS NEEDED — rows where AO (column AO) contains any of these strings: "Email 1", "Email 2", "Founder personal email", "Founder follow-up", "Final ask", "Final nudge", "WhatsApp / phone"

B) LINKEDIN MANUAL ACTIONS — rows where AO contains any of: "LinkedIn connect", "LinkedIn DM", "Engage on their LinkedIn", "Check LinkedIn"

C) ACTIVATION REMINDERS — rows where Track (column AI) = 1 (signed CPs needing weekly Pradeep nudge)

STEP 4 — RESEARCH PROSPECTS

For each row in bucket A (email drafts), research the prospect before drafting. Use the sales:draft-outreach skill or sales:account-research skill to look up:
- Their LinkedIn profile (column M) for recent posts, role details, firm focus
- Their organization for AUM, client type, specialization
- Any recent news or activity that could be a conversation hook

If the Sales plugin is not available, use web search as fallback. If no research is possible (no LinkedIn URL, generic name), note this and proceed with a generic-but-warm email.

STEP 5 — DRAFT EMAILS (EKA TONE)

First, read the tone reference document. Search Google Drive for a file named "eka_outreach_tone_guide" or look in the working folder for "eka_outreach_tone_guide.md". This document contains the exact email structures, subject line options, and voice rules for every track and step. Follow it precisely.

For each row in bucket A, compose an email following the EKA 9-touchpoint system tone. The core rules:

1. Lead with their pain, not your company name. Open with what matters to the prospect's clients.
2. Credibility first, numbers never in cold outreach. Mention IIMB, Blinkit, BigBasket, Samunnati, EBITDA positive.
3. One CTA per email. Either Calendly link OR "reply and I'll send the brief." Never both.
4. Short. Max 6-8 short paragraphs for emails. Max 3 lines for LinkedIn DMs.
5. P.S. line mandatory on Email 1 — use for social proof (peer names like Sridhar at B32) or urgency (Phase 1 closes 31 May).

Personalize by prospect tier. Read column G (Tier) for each row. The dropdown values are: WM, Family Office, NRI Advisor, RE Advisor, Other. Match the angle to the value:

- WM (Wealth Manager): lead with "Your clients earn 3-4% residential yield" / pre-empt capital protection.
- Family Office: lead with "One gap: real-asset product with operating income, not just appreciation".
- NRI Advisor: lead with "India exposure without India presence + tax-free Section 10(1)".
- RE Advisor: lead with "3-5% residential yield isn't cutting it".
- Other or blank: fall back to inferring from designation/org. Note this as a research gap so Jhalak can fill in column G later.

If column G is blank for a row, do NOT guess silently — explicitly log "Tier missing for [Prospect ID]" in the run summary. Tier should be filled at lead-add time; missing tiers are a data quality issue, not a daily decision.

TRACK 2 — Cold outreach (signed as Pradeep Ram, AgResearch Labs):
- D5/Email 1: Subject line A/B options: peer reference ("Sridhar at B32 is already in the founding cohort"), credibility hook ("Blinkit's farm supplier — now open to WM distribution"), or curiosity ("A real-asset product your HNI clients probably haven't seen"). Body: 1 para credibility + 1 para product (asset-backed LLP, ARL-operated, tax-free ag income Month 7, capital returned Year 5) + Calendly CTA. Mandatory P.S. with social proof.
- D8/Email 2: Reply to previous subject. One new fact (Phase 1 units, confirmations). One pre-empted objection rotated by tier. P.S. for CPs: commission teaser ("at base case — 3 investors at 2 Cr each — commission is ~40 Lakhs").
- D12/Engage: Flag for LinkedIn engagement. Find their recent post on real estate yields, alternatives, or HNI diversification. Comment with 1-2 line substantive perspective. No mention of EKA. No link.
- D18/Final nudge: Real date ("Phase 1 closes 31 May"). Referral ask ("If you know one advisor whose clients look at real-asset alternatives, I'd appreciate a name"). Phase 2 door open. Clean close, never desperate.

TRACK 3 — Warm referral (Jhalak's voice, mentioning Pradeep):
- W1/Warm Email 1: Open with referral: "Pradeep suggested I reach out" or "Pradeep mentioned your name in the context of..." Brief credibility (1 line). Product summary (2 lines). CTA: Calendly. Sign-off: "Warm regards, Jhalak"
- W2/Warm Follow-up: Shorter. Reference previous email. Add one new angle (site visit, peer reference, new data point). Sign-off: "Warm regards, Jhalak"
- W3/WA-Phone: Flag for WhatsApp/phone. If drafting WhatsApp text: 3 lines max, no links on first WhatsApp, curiosity only, end with "Worth a 15-min call this week?"

TRACK 4 — Founder close (Pradeep's voice — peer-to-peer):
- F1/Founder Email 1: Subject: "Quick thought / [Company Name]". Peer-to-peer opener referencing their specific firm and role. Confident founder energy — share, not sell. No hedging, no corporate speak. Growize value prop in THEIR language. CTA: 20-minute call. Sign-off: "Best, Pradeep"
- F2/Founder Follow-up: Reply to previous. One new credibility point or social proof. Shorter.
- F3/Founder Final Ask: Real close date. Referral ask. Phase 2 door open. Dignified close. Sign-off: "Best, Pradeep"

For all follow-up emails, reference the previous outreach and keep it shorter than the original.

IMPORTANT: Never fabricate credibility claims. Only use points found in the credibility doc from Step 2. If the doc was not found or was empty, keep emails generic but warm. Never invent peer names or statistics.

STEP 5B — HUMANIZE EMAILS (MANDATORY — DO NOT SKIP)

This step is non-negotiable. Every single email draft MUST be rewritten through this humanizer pass before proceeding to Step 6. No exceptions.

PASS 1 — Kill AI language. Search every draft for these phrases and DELETE or REWRITE them:
"I wanted to reach out", "I hope this finds you well", "I came across your profile", "I'd love to connect", "leveraging", "synergies", "exploring potential opportunities", "in this space", "on my radar", "aligns well with", "streamline", "cutting-edge", "game-changing", "innovative solution", "holistic approach", "robust", "scalable", "deep dive", "circle back", "move the needle", "low-hanging fruit", "best-in-class", "end-to-end", "ecosystem", "paradigm"

If ANY of these phrases survive into a final draft, the entire step has failed. Re-run from scratch.

PASS 2 — Sound human. Apply ALL of these rules to every draft:
- Use contractions: "we've" not "we have", "I'd" not "I would", "there's" not "there is", "don't" not "do not"
- Vary sentence length: mix 5-word punches with 25-word explanations. Never uniform rhythm.
- Add natural imperfections: dash instead of comma occasionally. Sentence fragment for emphasis. Start one sentence with "And" or "But".
- No perfect parallel structure: if you have 3 bullet-like sentences in a row with identical cadence, break the pattern.

PASS 3 — Voice match.
- Pradeep (Track 2 Email 1/2, Track 4): Confident founder energy. Built something real. Speaks directly. No hedging ("perhaps", "might be worth", "if you're open to"). Uses short declarative statements. Example: "We supply Blinkit and BigBasket. IIMB-incubated. EBITDA positive."
- Jhalak (Track 3): Sharp professional. Warm but efficient. Gets to the point in sentence one. Mentions Pradeep naturally, not formally.

PASS 4 — Read-aloud test. Read every email aloud mentally. If ANY phrase sounds like a template, AI, or marketing copy, rewrite that specific phrase. The email should sound like a busy professional typed it between meetings.

If the marketing:brand-review skill is available, use it as a final check on voice consistency. If not available, PASS 4 serves as the final gate.

STEP 6 — CREATE GMAIL DRAFTS

For each drafted email from Step 5B, use the Gmail create_draft tool:
- To: the prospect's email from column N
- Subject: per track voice guidelines from Step 5
- Body: the drafted email in HTML format (use <p> tags for paragraphs, <br> for line breaks within paragraphs)

Only create DRAFTS. Never send. If a prospect has no email in column N, skip the draft and note "missing email" in the summary.

If the Gmail connector is not available, skip this step entirely and include all draft text in the output file for manual copy-paste.

STEP 7 — SAVE DAILY SUMMARY

Write a markdown file named with today's date (e.g., outreach_2026-05-05.md). Structure it exactly as follows:

# Today's Outreach — [DATE]

**[X] email drafts created** | **[Y] manual LinkedIn actions** | **[Z] activation reminders**

> BLOCKERS: [list any — empty credibility doc, missing emails, Gmail not connected, plugins not available, etc. Write "None" if no blockers]

## EMAIL DRAFTS

[For each draft, include:]
### [Number]. [Prospect Name] — [Organization] (Track [N] / [Step Name])
- **To:** [email]
- **Subject:** [subject line]
- **Track:** [track number] ([track name], [sender]'s voice)
- **Step:** [step code] — [step name]

> [Full email body]

---

## LINKEDIN — MANUAL

| # | Prospect | Organization | LinkedIn URL | Action |
|---|----------|-------------|-------------|--------|
| [num] | [name] | [org] | [url] | [specific action to take] |

## ACTIVATION (Pradeep)

| # | CP Name | Organization | Days in Stage | Nudge About |
|---|---------|-------------|---------------|-------------|
| [num] | [name] | [org] | [days] | [what to nudge about] |

## SKIPPED ROWS

| ID | Name | Reason |
|----|------|--------|
| [id] | [name] | [reason skipped] |

## AFTER YOU ACT

Stamp today's date in the correct column after completing each action:

| Action | Column to Stamp |
|--------|----------------|
| LinkedIn connect sent | **S** (Connect Sent) |
| LinkedIn DM sent | **U** (First Message Date) |
| Cold Email 1 sent | **V** (Email 1 Date) |
| Cold Email 2 sent | **W** (Email 2 Date) |
| Cold follow-up / engagement | **X** (Follow-up Date) |
| Cold final nudge sent | **Y** (Final Nudge Date) |
| Warm referral email sent | **Z** (Warm Email 1) |
| Warm follow-up sent | **AA** (Warm Follow-up) |
| Warm WA/phone done | **AB** (Warm WA/Phone) |
| Founder email sent (Pradeep) | **AC** (Founder Email 1) |
| Founder follow-up sent | **AD** (Founder Follow-up) |
| Founder final ask sent | **AE** (Founder Final Ask) |

Also update these dropdowns as events happen:
- **AI** (Track) — change to 3 or 4 when formula shows ESCALATE
- **AJ** (Connect Accepted?) — set to Y or N when LinkedIn requests are accepted or rejected
- **AK** (Replied?) — set to Y when any reply lands on email, LinkedIn, or WhatsApp
- **AH** (Deal Stage) — update when calls or mandates happen (Call Booked / Call Done / Mandate Sent / Mandate Signed / Active)
- **G** (Tier) — fill at lead-add time. WM / Family Office / NRI Advisor / RE Advisor / Other (v4.2)
- **AT** (Archived) — tick when prospect is Won, Lost, or Dead-after-Track-4. Hides row from active workflow (v4.2)

---END PROMPT---

---

## Step 5: Deploy the Auto-Stamp Endpoint

The Apps Script includes a web endpoint that allows the evening reconciliation task to write dates and dropdown values directly into the sheet. This is optional but eliminates all manual date stamping.

1. Open the Google Sheet
2. Go to Extensions then Apps Script
3. In the script editor, click **Deploy** then **New deployment**
4. Set Type to **Web app**
5. Set Execute as to **Me** (jhalak.wadhwa@agresearchlabs.com)
6. Set Who has access to **Anyone with the link**
7. Click **Deploy** and authorize when prompted
8. Copy the deployment URL (it looks like `https://script.google.com/macros/s/.../exec`)
9. Set up a shared secret: in the Apps Script editor, go to **Project Settings** (gear icon on left), scroll to **Script Properties**, click **Add script property**, set Key = `STAMP_SECRET` and Value = any passphrase you choose (e.g. `growize-stamp-2026`)
10. Save the deployment URL and secret — you will need them in Step 6

To verify: open the deployment URL in a browser. You should see a JSON response like `{"status":"ok","sheet":"CP_Outreach","prospects":14,...}`

## Step 6: Create the Evening Reconciliation Task

This second scheduled task runs at 6 PM. It scans Gmail for emails you sent today and replies you received, cross-references them against the outreach sheet, and either auto-stamps dates (if the endpoint is deployed) or generates a precise checklist.

In Cowork, type:

> /schedule

When prompted, use these details:

- **Task name:** `evening-outreach-sync`
- **Schedule:** Every day at 6 PM except Sunday (cron: `0 18 * * 1-6`)
- **Prompt:** Copy-paste the entire prompt from the section below

---START PROMPT---

You are running the evening outreach reconciliation for Growize CP acquisition. This task detects what Jhalak did today and syncs the Google Sheet accordingly. Execute these steps in order.

STEP 1 — READ THE OUTREACH SHEET

Search Google Drive for the spreadsheet titled "Growize_CP_Outreach_Jhalak_Updated" (owned by jhalak.wadhwa@agresearchlabs.com, sheet ID: 1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4). Read the file content. Focus on the "CP_Outreach" tab.

Build a lookup of all prospects. For each row with a Prospect ID (column A), record:
- Prospect ID (A)
- Full Name (C)
- Organization (D)
- Email address (N)
- Current values of: S (Connect Sent), U (First Message), V (Email 1), W (Email 2), X (Follow-up), Y (Final Nudge)
- Track (AI)
- AK (Replied?)
- AO (Next Action — the action that WAS due this morning)

STEP 2 — SCAN GMAIL FOR SENT EMAILS

Search Gmail for emails sent today by Jhalak:

Query: `in:sent newer_than:1d`

For each sent email, extract the To address. Cross-reference against the prospect email addresses from Step 1. When a match is found, record:
- Which prospect received the email
- The subject line of the sent email

STEP 3 — SCAN GMAIL FOR REPLIES RECEIVED

Search Gmail for replies from any prospect email address. For each prospect who has an email in column N and whose AK is not already "Y":

Query: `from:{prospect_email} newer_than:1d`

If any results are found, that prospect has replied. Record:
- Prospect ID
- Prospect name
- The reply snippet/subject

STEP 4 — DETERMINE WHICH COLUMNS TO STAMP

For each prospect who received an email today (from Step 2), determine which column should be stamped based on the sheet's current state:

- If V (Email 1) is empty → this was Email 1, stamp **V**
- If V is filled but W (Email 2) is empty → this was Email 2, stamp **W**
- If W is filled but X (Follow-up) is empty → this was a follow-up, stamp **X**
- If X is filled but Y (Final Nudge) is empty → this was the final nudge, stamp **Y**
- If Y is already filled → sequence was already complete, note as "no stamp needed"

Cross-check against AO (Next Action) from this morning to validate: if AO said "D5: Send Email 1" and V is empty, stamping V is correct. If there is a mismatch, flag it but still proceed with the column-state-based logic above.

For each prospect who replied (from Step 3), mark:
- Column **AK** should be set to **Y**
- Column **AL** should be set to **Email**

STEP 5 — APPLY UPDATES OR GENERATE CHECKLIST

Option A — If the auto-stamp endpoint is deployed:

The Apps Script web app URL and secret should be stored. Make a POST request to the endpoint URL with this JSON body:

{
  "secret": "<the STAMP_SECRET passphrase>",
  "updates": [
    { "prospectId": "CP-PROS-003", "column": "V", "value": "YYYY-MM-DD" },
    { "prospectId": "CP-PROS-007", "column": "AK", "value": "Y" },
    { "prospectId": "CP-PROS-007", "column": "AL", "value": "Email" }
  ]
}

Use today's date for all date stamps. Report the endpoint response.

If the endpoint is not available or returns an error, fall back to Option B.

Option B — Generate a manual stamp checklist:

Create a clear, copy-paste-ready checklist that Jhalak can follow in one batch:

## Evening Sync — [DATE]

### EMAILS SENT TODAY (stamp dates)

| Row | Prospect | Org | Email Sent To | Column to Stamp | Value |
|-----|----------|-----|---------------|-----------------|-------|
| [row] | [name] | [org] | [email] | [V/W/X/Y] | [today's date] |

### REPLIES DETECTED (update dropdowns)

| Row | Prospect | Org | Reply Subject | Set AK to | Set AL to |
|-----|----------|-----|--------------|-----------|-----------|
| [row] | [name] | [org] | [subject snippet] | Y | Email |

### NO ACTION NEEDED

[List prospects where emails were expected but not found in Sent folder, or where stamps were already applied]

### LINKEDIN REMINDER

[List any prospects whose AO this morning was a LinkedIn action — these cannot be auto-detected. Remind Jhalak: "Did you do these LinkedIn actions today? If yes, stamp the following columns:"]

| Prospect | Action | Column to Stamp |
|----------|--------|-----------------|
| [name] | [LinkedIn connect / DM / engage] | [S / U / X] |

---END PROMPT---

---

## Step 7: Trial Run — End-to-End Verification

Run this trial to confirm every piece of the system works. Do it in order — each step builds on the previous one.

### Trial Part 1: Connectors

In Cowork, run these commands one at a time and check each result:

1. **Gmail:** Say "list my Gmail labels" — expect a list of labels. If it fails, reconnect Gmail (Step 1).
2. **Google Drive:** Say "search my Drive for Growize_CP_Outreach" — expect the sheet to appear. If it fails, reconnect Drive (Step 2).
3. **Plugins:** Say "list my skills" — expect to see `sales:draft-outreach` and `marketing:brand-review` in the list. If missing, install plugins (Step 3).

### Trial Part 2: Morning Task

1. In Cowork, say: **"Run the daily-cp-outreach task now"**
2. Wait for it to complete and check the output against this checklist:

| Check | What to look for | Pass? |
|-------|-----------------|-------|
| Sheet read | Output mentions prospect names and track numbers | |
| Credibility doc | Output either shows credibility points OR flags "not found/empty" as a blocker | |
| Categorization | Output separates email drafts, LinkedIn actions, and activation reminders | |
| Research | Each email draft references something specific about the prospect (role, firm, recent activity) | |
| EKA tone | Emails lead with prospect's pain, not ARL. Credibility woven in naturally. One CTA per email. | |
| Track 4 voice | Pradeep emails: confident founder energy, direct, peer-to-peer, "Best, Pradeep" sign-off | |
| Track 2 voice | Cold emails: signed as "Pradeep Ram, AgResearch Labs". Subject lines use peer names or curiosity hooks. P.S. line present on Email 1. | |
| Track 3 voice | Jhalak emails: mentions Pradeep naturally, warm but efficient, "Warm regards, Jhalak" sign-off | |
| Tier personalization | Email angle matches prospect type (WM = yield pain, NRI = tax-free + no presence, FO = operating income gap). Tier read from column G, NOT inferred (v4.2) | |
| Archived skip | Output explicitly skips any rows where AT (Archived) is TRUE; no drafts are produced for archived prospects (v4.2) | |
| Tier-missing log | If any active row has G blank, output flags "Tier missing for [Prospect ID]" rather than silently inferring (v4.2) | |
| Humanizer PASS 1 | Zero AI phrases survive ("I wanted to reach out", "leveraging", "synergies", "I hope this finds you well", etc.) | |
| Humanizer PASS 2 | Contractions used, sentence length varies, at least one "And" or "But" opener per email | |
| Humanizer PASS 4 | Read-aloud: sounds like a busy professional typed it between meetings, not like AI copy | |
| Gmail drafts | Check Gmail Drafts folder — drafts should appear with correct To addresses and subjects | |
| Summary file | A markdown file is saved with all sections: email drafts, LinkedIn manual, activation, skipped rows | |

3. Read 2-3 drafts aloud. They should sound like a busy professional typed them, not like AI copy.

### Trial Part 3: Send + Evening Task

1. Pick ONE Gmail draft from Part 2 and send it manually (this creates a sent email for the evening task to detect)
2. Wait 1-2 minutes for Gmail to index the sent email
3. In Cowork, say: **"Run the evening-outreach-sync task now"**
4. Check the output:

| Check | What to look for | Pass? |
|-------|-----------------|-------|
| Sent detection | The email you just sent appears as a detected sent email, matched to the right prospect | |
| Column logic | The task correctly identifies which column to stamp (V if Email 1 was empty, W if Email 2, etc.) | |
| Reply scan | Task reports scanning for replies (even if none found — should say "0 replies detected") | |
| Auto-stamp OR checklist | If endpoint deployed: reports stamping the date. If not: generates a clean checklist table | |
| LinkedIn reminder | Lists any LinkedIn actions from this morning that need manual stamping | |

### Trial Part 4: Auto-Stamp Endpoint (optional, only if Step 5 was done)

1. Open the Apps Script deployment URL in a browser — expect `{"status":"ok","sheet":"CP_Outreach","prospects":...}`
2. If the evening task used Option A (auto-stamp), open the Google Sheet and verify the date was actually written into the correct cell
3. If the date is there, the full end-to-end automation works — no manual date stamping needed for email actions

### If something fails

- **Morning task can't read sheet:** Check Drive connector, verify sheet ID `1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4`
- **No Gmail drafts created:** Check Gmail connector, verify prospect has an email in column N
- **Evening task doesn't detect sent email:** Make sure you sent the email from `jhalak.wadhwa@agresearchlabs.com`, not a different account
- **Auto-stamp endpoint returns error:** Check the STAMP_SECRET matches between Script Properties and the task, re-deploy if needed
- **Formulas blank in sheet:** Open sheet, Outreach menu, "Refresh formulas only"

---

## Troubleshooting

**"Sheet not found"** — The sheet is owned by Jhalak's Google account. Make sure Google Drive is connected with `jhalak.wadhwa@agresearchlabs.com`. The sheet ID is `1GDUuEe065MzGUtu4Bp_sjqflif9-ryTbDADsLUxC6W4`.

**"Gmail connector not available"** — Go back to Step 1 and reconnect. The task will still generate email drafts in the summary file even without Gmail, but they will need to be copy-pasted manually.

**"Credibility doc empty"** or **"Credibility doc not found"** — This is expected until Pradeep or Sahil populates the doc. Emails will be drafted without specific claims. This is noted as a blocker in the summary but does not stop the task.

**"Sales plugin not available"** — The task falls back to web search for prospect research. Install the Sales plugin per Step 3 for better results.

**Formulas show blank in AO/AQ columns** — Run the Apps Script: open the sheet, go to Extensions then Apps Script, then use the Outreach menu and select "Refresh formulas only".

**AO/AP shows blank for a prospect with data** — Check that column AI (Track) has a value (1, 2, 3, or 4). Formulas require a Track assignment to compute actions.

---

## What Jhalak Does Each Day

**Morning (after the 9 AM task runs):**

1. Open Gmail and check the Drafts folder
2. Review each draft, personalize further if needed
3. Send the emails
4. Do the LinkedIn manual actions listed in the summary
5. Update AJ (Connect Accepted?) when you check LinkedIn status throughout the day

**Evening (after the 6 PM task runs):**

If the auto-stamp endpoint is deployed: the evening task stamps dates and marks replies automatically. Just review its summary to confirm everything looks right.

If the endpoint is not deployed: the evening task generates a checklist. Open the sheet once, follow the checklist to batch-stamp all dates and mark any replies. This replaces the old workflow of context-switching to the sheet after every single email.

---

## Column Quick Reference

These are the date columns Jhalak stamps after acting. Everything else auto-updates.

| Column | Letter | Phase | What to stamp |
|--------|--------|-------|---------------|
| Connect Sent | S | Cold | LinkedIn connect request sent |
| Connected Date | T | Cold | LinkedIn connection accepted |
| First Message Date | U | Cold | LinkedIn DM sent |
| Email 1 Date | V | Cold | First cold email sent |
| Email 2 Date | W | Cold | Second cold email sent |
| Follow-up Date | X | Cold | LinkedIn engagement done |
| Final Nudge Date | Y | Cold | Final cold nudge sent |
| Warm Email 1 | Z | Warm | Warm referral email sent |
| Warm Follow-up | AA | Warm | Warm follow-up email sent |
| Warm WA/Phone | AB | Warm | WhatsApp or phone follow-up done |
| Founder Email 1 | AC | Founder | Pradeep personal email sent |
| Founder Follow-up | AD | Founder | Pradeep follow-up sent |
| Founder Final Ask | AE | Founder | Pradeep final ask sent |
| Call/Meeting Date | AG | Conversion | Call or meeting happened |

Auto-computed columns (do not edit manually):
- **P** (Current Stage) — derived from which date columns are filled
- **Q** (Stage Updated Date) — most recent action date
- **R** (Days in Stage) — days since last action, color-coded: green (0-2), yellow (3-5), orange (6-10), red (11+)
- **AO** (Next Action) — what to do next; blank when row is archived
- **AP** (Next Action Date) — when the next action is due; blank when row is archived
- **AQ** (Action Due?) — TODAY / OVERDUE / FUTURE; blank when row is archived
- **AR** (Status) — overall prospect status; "Archived" wins over everything else
- **AS** (Days In Track, v4.2) — days since the row entered its current Track; track-aware orange/red staleness coloring

Manually-edited support columns:
- **G** (Tier, v4.2) — fill at lead-add time. Drives email angle. WM / Family Office / NRI Advisor / RE Advisor / Other.
- **AT** (Archived, v4.2) — checkbox. Tick when prospect is Won, Lost, or Dead-after-Track-4. Hides row from active workflow.

---

## Sheet Formula Design Notes (for reviewers)

The AO (Next Action) formula decides *what* action to display. It uses `TODAY()` gates to suppress actions that are not yet due, showing "Wait" or "Awaiting founder action" instead.

The AP (Next Action Date) formula computes *when* the next step is due. It intentionally does NOT use `TODAY()` gates — it always returns the computed due date regardless of whether that date is past, present, or future.

The AQ (Action Due?) formula compares AP against TODAY() and returns a descriptive string:
- **OVERDUE (Xd) since dd-MMM** — past due, with days late and original due date
- **TODAY** — due today
- **dd-MMM (Xd away)** — future, with date and days remaining
- **(blank)** — no action pending (parked, replied, archived, sequence complete)

This three-column design means:
- AO tells you what to do (or "Wait" if nothing is due yet)
- AP tells you when the next step is due (even if it is in the future)
- AQ tells you the urgency level

The daily outreach task filters on AQ starting with "TODAY" or "OVERDUE" to find actionable rows.

When AO = "PARKED", "REPLIED — handle manually", or "SEQUENCE COMPLETE", AP returns blank (no date) and AQ returns blank. These rows are excluded from the daily filter.

When AT (Archived, v4.2) is TRUE, AO/AP/AQ all return blank and AR returns "Archived". Archived rows are excluded from the daily filter.

If Track (AI) is empty, all formula columns return blank except AR which shows "Not started".

AS (Days In Track, v4.2) computes days since the row entered its current Track. Distinct from R (Days in Stage), which counts days since the last action of any kind. AS catches dead-air per-track: a row idle in Track 2 for 14+ days is dying even if R looks fine because cold-phase actions still pull MAX.
