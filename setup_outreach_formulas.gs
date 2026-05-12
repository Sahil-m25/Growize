/**
 * Growize CP Outreach — Sheet Automation Setup (v3)
 *
 * One-time setup script for the CP_Outreach tracker. Adds Track / status /
 * formula columns, conditional formatting, and dropdown validation so the
 * sheet computes "what's due today" automatically.
 *
 * INSTALL:
 *   1. Open your sheet -> Extensions -> Apps Script
 *   2. Replace the Code.gs contents with this file
 *   3. Save (Ctrl+S / Cmd+S)
 *   4. Reload the sheet — an "Outreach" menu appears in the menu bar
 *   5. Outreach -> Run full setup (authorize when prompted)
 *
 * After setup, use Outreach -> Pre-populate tracks for existing prospects
 * to tag existing rows. Review and adjust manually as needed.
 *
 * Re-running "Run full setup" is safe — it overwrites formulas and resets
 * validation but leaves your data intact.
 *
 * CHANGES IN V2:
 *   - Column AF renamed from "Next Action" to "Stage Notes" (disambiguate)
 *   - Activation rows (Track 1 / Signed) always surface with AQ = "TODAY"
 *   - LinkedIn acceptance check wired into Track 2 sequence automatically
 *   - Track 2 dates anchored to Connect Sent (S) for consistent pacing
 *   - Track 4 includes D8 WhatsApp/phone step
 *   - Formulas extend to row 200
 *   - "FUTURE" state in AQ for not-yet-due actions
 *   - Connect Accepted uses Pending/Y/N dropdown
 *
 * CHANGES IN V3:
 *   - P (Current Stage), Q (Stage Updated Date), R (Days in Stage) now auto-derive
 *   - Staleness color coding on column R (green/yellow/orange/red)
 *   - Track 1 AP fix: moved inside SWITCH to eliminate nested-IF empty cell bug
 *
 * CHANGES IN V4 (Escalation Model):
 *   - Tracks 2/3/4 become escalation stages: Cold → Warm Referral → Founder Close
 *   - Each phase has dedicated date columns (no overlap, no clearing on escalation)
 *   - Z/AA/AB repurposed: Call Sched/Done/Outcome → Warm Email 1/Follow-up/WA-Phone
 *   - AC/AD/AE repurposed: Mandate Sent/Signed/Founder flag → Founder Email 1/Follow-up/Final
 *   - AG/AH repurposed: Next Followup/Notes → Call Date / Deal Stage dropdown
 *   - Track 2 ends with ESCALATE instead of SEQUENCE COMPLETE
 *   - Track 3 ends with ESCALATE; only Track 4 reaches SEQUENCE COMPLETE
 *   - Current Stage (P) shows full escalation pipeline
 *   - prepopulateExistingTracks defaults all new leads to Track 2
 *
 * CHANGES IN V4.1 (Data cleanup + formatting):
 *   - clearRepurposedColumns_() strips old text from Z-AE/AG/AH on setup
 *   - AQ formula wraps day arithmetic in INT() for clean integer display
 *   - Conditional formatting uses AP date comparison (not AQ string match)
 *   - AQ column gets dedicated colors: red (overdue), green (today), blue (future)
 *   - loadTestScenarios clears all date/dropdown columns before writing test data
 */

const CONFIG = {
  SHEET_NAME: 'CP_Outreach',
  HEADER_ROW: 2,
  DATA_START_ROW: 3,
  MAX_ROW: 200,
  COLS: {
    PROSPECT_ID: 1,        // A
    DATE_ADDED: 2,         // B
    FULL_NAME: 3,          // C
    ORG: 4,                // D
    DESIGNATION: 5,        // E
    CITY: 6,               // F
    PROFILE_TIER: 7,       // G
    SOURCE: 8,             // H
    SOURCE_DETAIL: 9,      // I
    MUTUAL_CONN: 10,       // J
    MUTUAL_NAME: 11,       // K
    MUTUAL_FOUNDER: 12,    // L
    LINKEDIN_URL: 13,      // M
    EMAIL: 14,             // N
    PHONE: 15,             // O
    CURRENT_STAGE: 16,     // P
    STAGE_DATE: 17,        // Q
    DAYS_IN_STAGE: 18,     // R
    CONNECT_SENT: 19,      // S
    CONNECTED_DATE: 20,    // T
    FIRST_MESSAGE: 21,     // U
    EMAIL_1: 22,           // V
    EMAIL_2: 23,           // W
    FOLLOWUP: 24,          // X
    FINAL_NUDGE: 25,       // Y  — end of cold phase
    WARM_EMAIL_1: 26,      // Z  (was Call Scheduled) — warm referral email
    WARM_FOLLOWUP: 27,     // AA (was Call Done) — warm follow-up email
    WARM_PHONE: 28,        // AB (was Call Outcome) — warm WA/phone nudge
    FOUNDER_EMAIL_1: 29,   // AC (was Mandate Sent) — founder personal email
    FOUNDER_FOLLOWUP: 30,  // AD (was Mandate Signed) — founder follow-up
    FOUNDER_FINAL: 31,     // AE (was Founder For Call) — founder final ask
    STAGE_NOTES: 32,       // AF  (renamed from "Next Action")
    CALL_DATE: 33,         // AG (was Next Followup) — call/meeting date
    DEAL_STAGE: 34,        // AH (was Notes) — conversion dropdown
    TRACK: 35,             // AI
    CONNECT_ACCEPTED: 36,  // AJ
    REPLIED: 37,           // AK
    REPLY_CHANNEL: 38,     // AL
    HALT: 39,              // AM
    SEED: 40,              // AN
    NEXT_ACTION: 41,       // AO
    NEXT_DATE: 42,         // AP
    ACTION_DUE: 43,        // AQ
    STATUS: 44             // AR
  }
};


// =====================================================================
// MENU
// =====================================================================

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Outreach')
    .addItem('Run full setup', 'setupOutreachAutomation')
    .addSeparator()
    .addItem('Refresh formulas only', 'refreshFormulas')
    .addItem('Pre-populate tracks for existing prospects', 'prepopulateExistingTracks')
    .addSeparator()
    .addItem('Load test scenarios (trial only)', 'loadTestScenarios')
    .addToUi();
}


// =====================================================================
// MAIN ENTRY POINTS
// =====================================================================

function setupOutreachAutomation() {
  const sheet = getSheet_();
  clearRepurposedColumns_(sheet);
  renameStageNotesHeader_(sheet);
  setHeaders_(sheet);
  setValidations_(sheet);
  writeFormulas_(sheet);
  setConditionalFormatting_(sheet);
  SpreadsheetApp.getUi().alert(
    'Setup complete (v4 — Escalation Model).\n\n' +
    'Columns Z-AE repurposed for warm/founder phases.\n' +
    'AG = Call Date, AH = Deal Stage dropdown.\n' +
    'Formulas installed for P/Q/R and AO-AR.\n\n' +
    'Track meanings:\n' +
    '  1 = Activation (signed CPs)\n' +
    '  2 = Cold outreach (starting point)\n' +
    '  3 = Warm referral (Jhalak + Pradeep mention)\n' +
    '  4 = Founder close (Pradeep sends)\n\n' +
    'Next: Outreach -> Pre-populate tracks for existing prospects.'
  );
}

function refreshFormulas() {
  const sheet = getSheet_();
  writeFormulas_(sheet);
  SpreadsheetApp.getUi().alert(
    'Formulas refreshed for rows ' + CONFIG.DATA_START_ROW + '-' + CONFIG.MAX_ROW + '.'
  );
}

function prepopulateExistingTracks() {
  const sheet = getSheet_();
  const lastRow = sheet.getLastRow();
  if (lastRow < CONFIG.DATA_START_ROW) {
    SpreadsheetApp.getUi().alert('No prospects found.');
    return;
  }

  const numRows = lastRow - CONFIG.DATA_START_ROW + 1;
  // Read cols A through P (16 columns) plus col AI (Track) to avoid overwriting manual entries
  const data = sheet.getRange(CONFIG.DATA_START_ROW, 1, numRows, 16).getValues();
  const existingTracks = sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.TRACK, numRows, 1).getValues();
  // Read Deal Stage (AH) to detect signed/active CPs
  const dealStages = sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.DEAL_STAGE, numRows, 1).getValues();

  const tracks = data.map(function(row, i) {
    // Skip if track already manually assigned
    if (existingTracks[i][0] !== '' && existingTracks[i][0] !== null) {
      return [existingTracks[i][0]];
    }

    const id = row[0];
    const stage = String(row[CONFIG.COLS.CURRENT_STAGE - 1] || '');
    const dealStage = String(dealStages[i][0] || '');

    if (!id) return [''];
    // Signed/Active CPs go to Track 1 (Activation)
    if (stage === 'Signed' || stage === 'Active' ||
        dealStage === 'Mandate Signed' || dealStage === 'Active') return ['1'];
    // All new prospects start at Track 2 (Cold). Escalation to 3/4 is manual.
    return ['2'];
  });

  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.TRACK, tracks.length, 1).setValues(tracks);

  // Default Connect Accepted? to "Pending" for Track 2 rows where it's blank
  const acceptedRange = sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.CONNECT_ACCEPTED, numRows, 1);
  const acceptedValues = acceptedRange.getValues();
  const newAccepted = acceptedValues.map(function(row, i) {
    if (String(tracks[i][0]) === '2' && !row[0]) return ['Pending'];
    return [row[0]];
  });
  acceptedRange.setValues(newAccepted);

  SpreadsheetApp.getUi().alert(
    'Tracks pre-populated.\n\n' +
    'Auto-assignment rules (only applied where Track was blank):\n' +
    '  Deal Stage = Signed/Active -> Track 1 (Activation)\n' +
    '  All others -> Track 2 (Cold outreach — starting point)\n\n' +
    'Escalation to Track 3 (Warm) or 4 (Founder) is done manually\n' +
    'when a cold sequence completes without a reply.'
  );
}


// =====================================================================
// INTERNAL HELPERS
// =====================================================================

/**
 * Clears old text/flag data from columns that were repurposed in v4.
 * Z-AE were Call Scheduled/Done/Outcome + Mandate Sent/Signed/Founder flag.
 * AG-AH were Next Followup/Notes. Old non-date text in these columns poisons
 * the v4 formulas (e.g. $AB<>"" returns TRUE from leftover text).
 *
 * Only clears cells that contain non-date values (strings, booleans, etc.)
 * to preserve any legitimate date stamps already entered under the v4 model.
 */
function clearRepurposedColumns_(sheet) {
  var repurposedCols = [
    CONFIG.COLS.WARM_EMAIL_1,    // Z  (was Call Scheduled)
    CONFIG.COLS.WARM_FOLLOWUP,   // AA (was Call Done)
    CONFIG.COLS.WARM_PHONE,      // AB (was Call Outcome)
    CONFIG.COLS.FOUNDER_EMAIL_1, // AC (was Mandate Sent)
    CONFIG.COLS.FOUNDER_FOLLOWUP,// AD (was Mandate Signed)
    CONFIG.COLS.FOUNDER_FINAL,   // AE (was Founder For Call)
    CONFIG.COLS.CALL_DATE,       // AG (was Next Followup)
    CONFIG.COLS.DEAL_STAGE       // AH (was Notes — clear non-dropdown text)
  ];

  var numRows = CONFIG.MAX_ROW - CONFIG.DATA_START_ROW + 1;
  var dealStageOptions = ['None', 'Call Booked', 'Call Done', 'Mandate Sent', 'Mandate Signed', 'Active', ''];

  repurposedCols.forEach(function(col) {
    var range = sheet.getRange(CONFIG.DATA_START_ROW, col, numRows, 1);
    var values = range.getValues();
    var changed = false;

    for (var i = 0; i < values.length; i++) {
      var v = values[i][0];
      if (v === '' || v === null) continue;

      if (col === CONFIG.COLS.DEAL_STAGE) {
        // For AH: keep valid dropdown values, clear anything else
        if (dealStageOptions.indexOf(String(v)) === -1) {
          values[i][0] = '';
          changed = true;
        }
      } else {
        // For date columns: keep actual Date objects, clear text/booleans
        if (!(v instanceof Date)) {
          values[i][0] = '';
          changed = true;
        }
      }
    }

    if (changed) {
      range.setValues(values);
    }
  });
}

function getSheet_() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(CONFIG.SHEET_NAME);
  if (!sheet) {
    throw new Error(
      'Sheet "' + CONFIG.SHEET_NAME + '" not found. ' +
      'Update SHEET_NAME in CONFIG if your tab has a different name.'
    );
  }
  return sheet;
}

function renameStageNotesHeader_(sheet) {
  // Disambiguate: AF was also called "Next Action" — rename to "Stage Notes"
  var current = sheet.getRange(CONFIG.HEADER_ROW, CONFIG.COLS.STAGE_NOTES).getValue();
  if (current === 'Next Action' || current === '' || current === 'Stage Notes') {
    sheet.getRange(CONFIG.HEADER_ROW, CONFIG.COLS.STAGE_NOTES)
      .setValue('Stage Notes')
      .setFontWeight('bold')
      .setBackground('#cfe2f3');
  }
}

function setHeaders_(sheet) {
  const headers = [
    // Warm phase columns (repurposed)
    [CONFIG.COLS.WARM_EMAIL_1, 'Warm Email 1'],
    [CONFIG.COLS.WARM_FOLLOWUP, 'Warm Follow-up'],
    [CONFIG.COLS.WARM_PHONE, 'Warm WA/Phone'],
    // Founder phase columns (repurposed)
    [CONFIG.COLS.FOUNDER_EMAIL_1, 'Founder Email 1'],
    [CONFIG.COLS.FOUNDER_FOLLOWUP, 'Founder Follow-up'],
    [CONFIG.COLS.FOUNDER_FINAL, 'Founder Final Ask'],
    // Conversion (repurposed)
    [CONFIG.COLS.CALL_DATE, 'Call/Meeting Date'],
    [CONFIG.COLS.DEAL_STAGE, 'Deal Stage'],
    // Track and dropdowns
    [CONFIG.COLS.TRACK, 'Track'],
    [CONFIG.COLS.CONNECT_ACCEPTED, 'Connect Accepted?'],
    [CONFIG.COLS.REPLIED, 'Replied?'],
    [CONFIG.COLS.REPLY_CHANNEL, 'Reply Channel'],
    [CONFIG.COLS.HALT, 'Halt?'],
    [CONFIG.COLS.SEED, 'Personalization Seed'],
    [CONFIG.COLS.NEXT_ACTION, 'Next Action'],
    [CONFIG.COLS.NEXT_DATE, 'Next Action Date'],
    [CONFIG.COLS.ACTION_DUE, 'Action Due?'],
    [CONFIG.COLS.STATUS, 'Status']
  ];

  headers.forEach(function(h) {
    sheet.getRange(CONFIG.HEADER_ROW, h[0])
      .setValue(h[1])
      .setFontWeight('bold')
      .setBackground('#cfe2f3');
  });
}

function setValidations_(sheet) {
  const numRows = CONFIG.MAX_ROW - CONFIG.DATA_START_ROW + 1;
  const range = function(col) {
    return sheet.getRange(CONFIG.DATA_START_ROW, col, numRows, 1);
  };

  range(CONFIG.COLS.TRACK).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['1', '2', '3', '4'], true)
      .setAllowInvalid(false)
      .setHelpText('1=Activation, 2=Cold outreach, 3=Warm referral (Jhalak+Pradeep), 4=Founder close (Pradeep)')
      .build()
  );

  range(CONFIG.COLS.CONNECT_ACCEPTED).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['Pending', 'Y', 'N'], true)
      .setAllowInvalid(false)
      .build()
  );

  range(CONFIG.COLS.REPLIED).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['Y', 'N'], true)
      .setAllowInvalid(false)
      .build()
  );

  range(CONFIG.COLS.REPLY_CHANNEL).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['LinkedIn', 'Email', 'Phone', 'WhatsApp'], true)
      .setAllowInvalid(false)
      .build()
  );

  range(CONFIG.COLS.HALT).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['Y', 'N'], true)
      .setAllowInvalid(false)
      .build()
  );

  // Date validation for all action-date columns
  // Enforces date-only input and consistent format
  var dateValidation = SpreadsheetApp.newDataValidation()
    .requireDate()
    .setAllowInvalid(false)
    .setHelpText('Enter a valid date (dd-MMM-yyyy or use the date picker)')
    .build();

  var dateCols = [
    CONFIG.COLS.CONNECT_SENT,    // S  — cold
    CONFIG.COLS.CONNECTED_DATE,  // T  — cold
    CONFIG.COLS.FIRST_MESSAGE,   // U  — cold
    CONFIG.COLS.EMAIL_1,         // V  — cold
    CONFIG.COLS.EMAIL_2,         // W  — cold
    CONFIG.COLS.FOLLOWUP,        // X  — cold
    CONFIG.COLS.FINAL_NUDGE,     // Y  — cold
    CONFIG.COLS.WARM_EMAIL_1,    // Z  — warm
    CONFIG.COLS.WARM_FOLLOWUP,   // AA — warm
    CONFIG.COLS.WARM_PHONE,      // AB — warm
    CONFIG.COLS.FOUNDER_EMAIL_1, // AC — founder
    CONFIG.COLS.FOUNDER_FOLLOWUP,// AD — founder
    CONFIG.COLS.FOUNDER_FINAL,   // AE — founder
    CONFIG.COLS.CALL_DATE        // AG — conversion
  ];

  dateCols.forEach(function(col) {
    range(col).setDataValidation(dateValidation);
  });

  // Set date format for these columns so display is consistent
  dateCols.forEach(function(col) {
    range(col).setNumberFormat('dd-MMM-yyyy');
  });

  // Also format Date Added (B) for consistency
  range(CONFIG.COLS.DATE_ADDED).setDataValidation(dateValidation);
  range(CONFIG.COLS.DATE_ADDED).setNumberFormat('dd-MMM-yyyy');

  // Deal Stage dropdown (AH) — conversion tracking
  range(CONFIG.COLS.DEAL_STAGE).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['None', 'Call Booked', 'Call Done', 'Mandate Sent', 'Mandate Signed', 'Active'], true)
      .setAllowInvalid(false)
      .setHelpText('Track conversion progress. Once "Mandate Signed", change Track to 1 (Activation)')
      .build()
  );
}

function writeFormulas_(sheet) {
  const numRows = CONFIG.MAX_ROW - CONFIG.DATA_START_ROW + 1;

  const currentStage = [];
  const stageDate = [];
  const daysInStage = [];
  const nextAction = [];
  const nextDate = [];
  const actionDue = [];
  const status = [];

  for (let i = 0; i < numRows; i++) {
    const r = CONFIG.DATA_START_ROW + i;
    currentStage.push([buildCurrentStageFormula_(r)]);
    stageDate.push([buildStageDateFormula_(r)]);
    daysInStage.push([buildDaysInStageFormula_(r)]);
    nextAction.push([buildNextActionFormula_(r)]);
    nextDate.push([buildNextDateFormula_(r)]);
    actionDue.push([buildActionDueFormula_(r)]);
    status.push([buildStatusFormula_(r)]);
  }

  // P, Q, R — auto-derived stage tracking
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.CURRENT_STAGE, numRows, 1).setFormulas(currentStage);
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.STAGE_DATE, numRows, 1).setFormulas(stageDate);
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.DAYS_IN_STAGE, numRows, 1).setFormulas(daysInStage);

  // AO, AP, AQ, AR — action progression
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.NEXT_ACTION, numRows, 1).setFormulas(nextAction);
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.NEXT_DATE, numRows, 1).setFormulas(nextDate);
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.ACTION_DUE, numRows, 1).setFormulas(actionDue);
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.STATUS, numRows, 1).setFormulas(status);

  // Format date columns
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.STAGE_DATE, numRows, 1)
    .setNumberFormat('dd-mmm-yyyy');
  sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.NEXT_DATE, numRows, 1)
    .setNumberFormat('dd-mmm-yyyy');
}

function setConditionalFormatting_(sheet) {
  const range = sheet.getRange('A' + CONFIG.DATA_START_ROW + ':AR' + CONFIG.MAX_ROW);
  const r = CONFIG.DATA_START_ROW;

  // Order matters: rules evaluated top-down, first match wins.
  // Halted/Replied take precedence so quiet rows stay quiet.
  const rules = [
    // Halted rows -> dark gray
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=$AM' + r + '="Y"')
      .setBackground('#cccccc')
      .setRanges([range])
      .build(),
    // Replied rows -> light gray
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=$AK' + r + '="Y"')
      .setBackground('#efefef')
      .setRanges([range])
      .build(),
    // Overdue rows -> light red (AP date is before today)
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND($AP' + r + '<>"",$AP' + r + '<TODAY())')
      .setBackground('#f4cccc')
      .setRanges([range])
      .build(),
    // Today rows -> light green (AP date is today)
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND($AP' + r + '<>"",$AP' + r + '=TODAY())')
      .setBackground('#d9ead3')
      .setRanges([range])
      .build(),
    // Activation rows -> light gold
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=$AI' + r + '=1')
      .setBackground('#fce5cd')
      .setRanges([range])
      .build()
  ];

  // --- Staleness colors on Days in Stage (column R) ---
  var rCol = sheet.getRange('R' + CONFIG.DATA_START_ROW + ':R' + CONFIG.MAX_ROW);

  // STALE: > 10 days — red
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberGreaterThan(10)
      .setBackground('#f4cccc')
      .setFontColor('#990000')
      .setRanges([rCol])
      .build()
  );
  // Cooling: 6-10 days — orange
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberBetween(6, 10)
      .setBackground('#fce5cd')
      .setFontColor('#7f6011')
      .setRanges([rCol])
      .build()
  );
  // OK: 3-5 days — yellow
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberBetween(3, 5)
      .setBackground('#fff2cc')
      .setRanges([rCol])
      .build()
  );
  // Fresh: 0-2 days — green
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberLessThanOrEqualTo(2)
      .setBackground('#d9ead3')
      .setRanges([rCol])
      .build()
  );

  // --- AQ column-specific formatting (Action Due?) ---
  var aqCol = sheet.getRange('AQ' + CONFIG.DATA_START_ROW + ':AQ' + CONFIG.MAX_ROW);

  // OVERDUE -> red background + dark red text
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND($AP' + r + '<>"",$AP' + r + '<TODAY())')
      .setBackground('#f4cccc')
      .setFontColor('#990000')
      .setBold(true)
      .setRanges([aqCol])
      .build()
  );
  // TODAY -> green background + dark green text
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND($AP' + r + '<>"",$AP' + r + '=TODAY())')
      .setBackground('#d9ead3')
      .setFontColor('#274e13')
      .setBold(true)
      .setRanges([aqCol])
      .build()
  );
  // Future -> light blue background
  rules.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND($AP' + r + '<>"",$AP' + r + '>TODAY())')
      .setBackground('#cfe2f3')
      .setFontColor('#1155cc')
      .setRanges([aqCol])
      .build()
  );

  sheet.setConditionalFormatRules(rules);
}


// =====================================================================
// FORMULA BUILDERS — STAGE TRACKING (P, Q, R)
// =====================================================================
//
// These derive Current Stage, Stage Updated Date, and Days in Stage
// automatically from which date columns are stamped. Jhalak stamps ONE
// date after acting — everything else computes itself.

function buildCurrentStageFormula_(r) {
  // Priority: highest completed action wins.
  // v4: full escalation pipeline — cold → warm → founder, with Deal Stage overlay.
  return [
    '=IF($A' + r + '="","",',
    'IFS(',
      // Conversion stages (Deal Stage dropdown takes top priority)
      'OR($AH' + r + '="Mandate Signed",$AH' + r + '="Active"),"Signed",',
      '$AH' + r + '="Mandate Sent","Mandate Sent",',
      '$AH' + r + '="Call Done","Call Done",',
      '$AH' + r + '="Call Booked","Call Booked",',
      // Founder close phase (Track 4 columns)
      '$AE' + r + '<>"","Founder Final",',
      '$AD' + r + '<>"","Founder Follow-up",',
      '$AC' + r + '<>"","Founder Contacted",',
      // Warm referral phase (Track 3 columns)
      '$AB' + r + '<>"","Warm Final",',
      '$AA' + r + '<>"","Warm Follow-up",',
      '$Z' + r + '<>"","Warm Contacted",',
      // Replied (can happen at any phase)
      '$AK' + r + '="Y","Replied",',
      // Cold outreach phase (Track 2 columns)
      'OR($Y' + r + '<>"",$X' + r + '<>"",$W' + r + '<>""),"Cold Follow-up",',
      '$V' + r + '<>"","Email Sent",',
      '$U' + r + '<>"","DM Sent",',
      '$T' + r + '<>"","Connected",',
      '$S' + r + '<>"","Connect Sent",',
      'TRUE,"Identified"',
    '))'
  ].join('');
}

function buildStageDateFormula_(r) {
  // Most recent action date = stage change date. Falls back to Date Added.
  // v4: includes warm (Z/AA/AB), founder (AC/AD/AE), and call (AG) columns.
  return [
    '=IF($A' + r + '="","",',
    'LET(latest,MAX($S' + r + ',$T' + r + ',$U' + r + ',$V' + r + ',$W' + r + ',',
      '$X' + r + ',$Y' + r + ',$Z' + r + ',$AA' + r + ',$AB' + r + ',',
      '$AC' + r + ',$AD' + r + ',$AE' + r + ',$AG' + r + '),',
    'IF(latest>0,latest,$B' + r + ')))'
  ].join('');
}

function buildDaysInStageFormula_(r) {
  // Days since last action (or since added if no actions taken)
  return '=IF(OR($A' + r + '="",$Q' + r + '=""),"",TODAY()-$Q' + r + ')';
}


// =====================================================================
// FORMULA BUILDERS — ACTION PROGRESSION (AO, AP, AQ, AR)
// =====================================================================
//
// Each function takes a row number and returns a Google Sheets formula
// string with cell references for that row. Edit these to change the
// outreach playbook.
//
// SEQUENCE OVERVIEW (v4 — Escalation Model):
//
//   Track 1 (Activation):  Already signed -> weekly Pradeep nudge
//
//   Track 2 (Cold Outreach — Jhalak sends cold):
//     D1  Send LinkedIn connect (no note)
//     D3  Check LinkedIn — has connect been accepted?
//     D3  Send LinkedIn DM (if accepted) / D5 Email 1 (if rejected/timeout)
//     D5  Send Email 1
//     D8  Send Email 2
//     D12 Engage on their LinkedIn post
//     D18 Send final nudge
//     → ESCALATE: set Track to 3, start warm phase
//
//   Track 3 (Warm Referral — Jhalak sends, mentions Pradeep):
//     W1  Warm referral email (stamp Z)
//     W2  Warm follow-up email (stamp AA, Z+3 days)
//     W3  Warm WA/phone nudge (stamp AB, AA+4 days)
//     → ESCALATE: set Track to 4, start founder phase
//
//   Track 4 (Founder Close — Pradeep sends personally):
//     F1  Founder personal email (stamp AC)
//     F2  Founder follow-up email (stamp AD, AC+6 days)
//     F3  Founder final ask (stamp AE, AD+7 days)
//     → SEQUENCE COMPLETE (true terminal state)

function buildNextActionFormula_(r) {
  return [
    '=IF($A' + r + '="","",',
    'IFERROR(',
    'SWITCH($AI' + r + ',',

      // --- Track 1: Activation (signed CPs) ---
      '1,"ACTIVATION — Pradeep weekly nudge",',

      // --- Track 2: Cold Outreach (Jhalak sends cold) ---
      // Columns: S, T, U, V, W, X, Y
      // Ends with ESCALATE instead of SEQUENCE COMPLETE
      '2,IFS(',
        '$AM' + r + '="Y","PARKED",',
        '$AK' + r + '="Y","REPLIED — handle manually",',
        '$S' + r + '="","D1: Send LinkedIn connect (no note)",',
        'AND(OR($AJ' + r + '="Pending",$AJ' + r + '=""),TODAY()>=$S' + r + '+2),"Check LinkedIn — has connect been accepted?",',
        'AND(OR($AJ' + r + '="Pending",$AJ' + r + '=""),TODAY()<$S' + r + '+2),"Wait — LinkedIn connect pending",',
        'AND($AJ' + r + '="N",$V' + r + '=""),"D5: Send Email 1 (LI not accepted)",',
        'AND($AJ' + r + '="Y",$U' + r + '="",$V' + r + '=""),"D3: Send LinkedIn DM",',
        'AND($AJ' + r + '="Y",$U' + r + '<>"",$V' + r + '="",TODAY()>=$U' + r + '+2),"D5: Send Email 1",',
        'AND($V' + r + '="",$S' + r + '<>"",TODAY()>=$S' + r + '+4),"D5: Send Email 1",',
        'AND($V' + r + '<>"",$W' + r + '="",TODAY()>=$V' + r + '+3),"D8: Send Email 2",',
        'AND($W' + r + '<>"",$X' + r + '="",TODAY()>=$W' + r + '+4),"D12: Engage on their LinkedIn post",',
        'AND($X' + r + '<>"",$Y' + r + '="",TODAY()>=$X' + r + '+6),"D18: Send final nudge",',
        '$Y' + r + '<>"","ESCALATE — Change Track to 3",',
        'TRUE,"Wait"',
      '),',

      // --- Track 3: Warm Referral (Jhalak sends, mentions Pradeep) ---
      // Columns: Z (Warm Email 1), AA (Warm Follow-up), AB (Warm WA/Phone)
      // Ends with ESCALATE
      '3,IFS(',
        '$AM' + r + '="Y","PARKED",',
        '$AK' + r + '="Y","REPLIED — handle manually",',
        '$Z' + r + '="","W1: Send warm referral email",',
        'AND($Z' + r + '<>"",$AA' + r + '="",TODAY()>=$Z' + r + '+3),"W2: Send warm follow-up email",',
        'AND($AA' + r + '<>"",$AB' + r + '="",TODAY()>=$AA' + r + '+4),"W3: WhatsApp / phone nudge",',
        '$AB' + r + '<>"","ESCALATE — Change Track to 4",',
        'TRUE,"Wait — warm follow-up pending"',
      '),',

      // --- Track 4: Founder Close (Pradeep sends personally) ---
      // Columns: AC (Founder Email 1), AD (Founder Follow-up), AE (Founder Final)
      // True terminal state: SEQUENCE COMPLETE
      '4,IFS(',
        '$AM' + r + '="Y","PARKED",',
        '$AK' + r + '="Y","REPLIED — handle manually",',
        '$AC' + r + '="","F1: Founder personal email (Pradeep sends)",',
        'AND($AC' + r + '<>"",$AD' + r + '="",TODAY()>=$AC' + r + '+6),"F2: Founder follow-up email",',
        'AND($AD' + r + '<>"",$AE' + r + '="",TODAY()>=$AD' + r + '+7),"F3: Founder final ask",',
        '$AE' + r + '<>"","SEQUENCE COMPLETE",',
        'TRUE,"Awaiting founder action"',
      '),',

      '""',
    '),',
    '"")',
    ')'
  ].join('');
}

function buildNextDateFormula_(r) {
  // v4.1: Escalation dates anchor to the PREVIOUS PHASE'S end date, not TODAY().
  // This way if Jhalak delays escalation, the row correctly shows OVERDUE.
  //
  // Track 2 ESCALATE → due = Y (cold end date)
  // Track 3 W1       → due = Y (when cold ended) or B (fallback)
  // Track 3 ESCALATE → due = AB (warm end date)
  // Track 4 F1       → due = AB (when warm ended) or Y or B (fallback)
  return [
    '=IF(OR($A' + r + '="",$AO' + r + '=""),"",',
    'IFERROR(',
    'SWITCH($AI' + r + ',',

      // --- Track 1: Activation — always due today ---
      '1,TODAY(),',

      // --- Track 2 dates (Cold — columns S through Y) ---
      '2,IFS(',
        'OR($AM' + r + '="Y",$AK' + r + '="Y"),"",',
        '$S' + r + '="",$B' + r + ',',                       // D1: due on Date Added
        'AND(OR($AJ' + r + '="Pending",$AJ' + r + '=""),TODAY()>=$S' + r + '+2),TODAY(),',
        'AND(OR($AJ' + r + '="Pending",$AJ' + r + '=""),TODAY()<$S' + r + '+2),$S' + r + '+2,',
        'AND($AJ' + r + '="N",$V' + r + '=""),MAX(TODAY(),$S' + r + '+4),',
        'AND($AJ' + r + '="Y",$U' + r + '="",$V' + r + '=""),$S' + r + '+2,',
        'AND($AJ' + r + '="Y",$U' + r + '<>"",$V' + r + '=""),$U' + r + '+2,',
        'AND($V' + r + '="",$S' + r + '<>""),$S' + r + '+4,',
        '$W' + r + '="",$V' + r + '+3,',                     // D8
        '$X' + r + '="",$W' + r + '+4,',                     // D12
        '$Y' + r + '="",$X' + r + '+6,',                     // D18
        '$Y' + r + '<>"",$Y' + r + ',',                      // ESCALATE: due = cold end date
        'TRUE,""',
      '),',

      // --- Track 3 dates (Warm Referral — columns Z, AA, AB) ---
      '3,IFS(',
        'OR($AM' + r + '="Y",$AK' + r + '="Y"),"",',
        '$Z' + r + '="",IF($Y' + r + '<>"",$Y' + r + ',$B' + r + '),',  // W1: due = cold end date (or Date Added)
        '$AA' + r + '="",$Z' + r + '+3,',     // W2: Z + 3 days
        '$AB' + r + '="",$AA' + r + '+4,',    // W3: AA + 4 days
        '$AB' + r + '<>"",$AB' + r + ',',     // ESCALATE: due = warm end date
        'TRUE,""',
      '),',

      // --- Track 4 dates (Founder Close — columns AC, AD, AE) ---
      '4,IFS(',
        'OR($AM' + r + '="Y",$AK' + r + '="Y"),"",',
        '$AC' + r + '="",IF($AB' + r + '<>"",$AB' + r + ',IF($Y' + r + '<>"",$Y' + r + ',$B' + r + ')),',  // F1: due = warm end (or cold end, or Date Added)
        '$AD' + r + '="",$AC' + r + '+6,',    // F2: AC + 6 days
        '$AE' + r + '="",$AD' + r + '+7,',    // F3: AD + 7 days
        'TRUE,""',
      '),',

      '""',
    '),',
    '""))'
  ].join('');
}

function buildActionDueFormula_(r) {
  // v4.1: AQ now shows context — how many days overdue, or when future items are due.
  // Format: "OVERDUE (5d) since 29-Apr" | "TODAY" | "09-May (5d away)"
  return [
    '=IF(OR($A' + r + '="",$AP' + r + '=""),"",',
    'IF(INT($AP' + r + ')<TODAY(),',
      '"OVERDUE ("&INT(TODAY()-$AP' + r + ')&"d) since "&TEXT($AP' + r + ',"dd-MMM"),',
    'IF(INT($AP' + r + ')=TODAY(),',
      '"TODAY",',
      'TEXT($AP' + r + ',"dd-MMM")&" ("&INT($AP' + r + '-TODAY())&"d away)"',
    ')))'
  ].join('');
}

function buildStatusFormula_(r) {
  // v4.1: uses AP date comparison instead of AQ string matching
  // (since AQ now contains descriptive text, not bare keywords)
  return [
    '=IF($A' + r + '="","",',
    'IF($AP' + r + '="",',
      'IFS(',
        '$AM' + r + '="Y","Parked",',
        '$AK' + r + '="Y","Replied",',
        '$AI' + r + '=1,"Activation",',
        '$AO' + r + '="SEQUENCE COMPLETE","Sequence complete",',
        'LEFT($AO' + r + ',8)="ESCALATE","Needs escalation",',
        'OR($S' + r + '<>"",$Z' + r + '<>"",$AC' + r + '<>""),"In progress",',
        'TRUE,"Not started"',
      '),',
      'IFS(',
        '$AM' + r + '="Y","Parked",',
        '$AK' + r + '="Y","Replied",',
        '$AI' + r + '=1,"Activation",',
        '$AO' + r + '="SEQUENCE COMPLETE","Sequence complete",',
        'LEFT($AO' + r + ',8)="ESCALATE","Needs escalation",',
        '$AP' + r + '<TODAY(),"Overdue",',
        '$AP' + r + '=TODAY(),"Action today",',
        '$AP' + r + '>TODAY(),"Upcoming",',
        'TRUE,"In progress"',
      ')',
    '))'
  ].join('');
}


// =====================================================================
// TEST SCENARIOS (trial sheet only)
// =====================================================================
// Writes sample dates into rows 3-13 to simulate prospects at different
// stages.  Run AFTER "Run full setup" so formulas are in place.
// Then check AP/AQ/AR to confirm each row shows a different computed date.

function loadTestScenarios() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.alert(
    'Load Test Scenarios (v4 — Escalation Model)',
    'This will overwrite date columns (S-AE), dropdowns (AJ/AK/AM/AH), for rows 3-17 with test data.\n\n' +
    'Only use this on the TRIAL copy, not on Jhalak\'s production sheet.\n\nContinue?',
    ui.ButtonSet.OK_CANCEL
  );
  if (resp !== ui.Button.OK) return;

  var sheet = getSheet_();

  // Helper: create local-timezone date (month is 1-indexed for readability).
  function d(y, m, day) { return new Date(y, m - 1, day); }

  // Clear repurposed columns (Z-AE, AG, AH) and dropdowns for test rows 5-17
  // to prevent old text data from poisoning v4 formulas.
  var testRowStart = 5;
  var testRowCount = 13; // rows 5-17
  var clearCols = [
    CONFIG.COLS.WARM_EMAIL_1, CONFIG.COLS.WARM_FOLLOWUP, CONFIG.COLS.WARM_PHONE,
    CONFIG.COLS.FOUNDER_EMAIL_1, CONFIG.COLS.FOUNDER_FOLLOWUP, CONFIG.COLS.FOUNDER_FINAL,
    CONFIG.COLS.CALL_DATE, CONFIG.COLS.DEAL_STAGE,
    CONFIG.COLS.CONNECT_ACCEPTED, CONFIG.COLS.REPLIED, CONFIG.COLS.REPLY_CHANNEL,
    CONFIG.COLS.HALT
  ];
  clearCols.forEach(function(col) {
    sheet.getRange(testRowStart, col, testRowCount, 1).clearContent();
  });
  // Also clear cold date columns for clean test state
  var coldCols = [
    CONFIG.COLS.CONNECT_SENT, CONFIG.COLS.CONNECTED_DATE, CONFIG.COLS.FIRST_MESSAGE,
    CONFIG.COLS.EMAIL_1, CONFIG.COLS.EMAIL_2, CONFIG.COLS.FOLLOWUP, CONFIG.COLS.FINAL_NUDGE
  ];
  coldCols.forEach(function(col) {
    sheet.getRange(testRowStart, col, testRowCount, 1).clearContent();
  });

  // ---- TRACK 2 (COLD) SCENARIOS ----

  // CP-PROS-003 (row 5) — Track 2, connect sent 20-Apr, pending acceptance
  // Expected: AO = "Check LinkedIn", AP = 22-Apr, AQ = OVERDUE
  sheet.getRange(5, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 20));

  // CP-PROS-004 (row 6) — Track 2, connect accepted, DM sent, waiting for Email 1
  // Expected: AO = "D5: Send Email 1", AP = 22-Apr, AQ = OVERDUE
  sheet.getRange(6, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 18));
  sheet.getRange(6, CONFIG.COLS.CONNECT_ACCEPTED).setValue('Y');
  sheet.getRange(6, CONFIG.COLS.FIRST_MESSAGE).setValue(d(2026, 4, 20));

  // CP-PROS-005 (row 7) — Track 2, connect REJECTED, Email 1 sent, Email 2 due
  // Expected: AO = "D8: Send Email 2", AP = 28-Apr, AQ = OVERDUE
  sheet.getRange(7, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 15));
  sheet.getRange(7, CONFIG.COLS.CONNECT_ACCEPTED).setValue('N');
  sheet.getRange(7, CONFIG.COLS.EMAIL_1).setValue(d(2026, 4, 25));

  // CP-PROS-006 (row 8) — Track 2, cold sequence COMPLETE, ready to escalate
  // Expected: AO = "ESCALATE — Change Track to 3", AP = TODAY, AQ = TODAY, AR = Needs escalation
  sheet.getRange(8, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 10));
  sheet.getRange(8, CONFIG.COLS.CONNECT_ACCEPTED).setValue('Y');
  sheet.getRange(8, CONFIG.COLS.FIRST_MESSAGE).setValue(d(2026, 4, 12));
  sheet.getRange(8, CONFIG.COLS.EMAIL_1).setValue(d(2026, 4, 14));
  sheet.getRange(8, CONFIG.COLS.EMAIL_2).setValue(d(2026, 4, 17));
  sheet.getRange(8, CONFIG.COLS.FOLLOWUP).setValue(d(2026, 4, 21));
  sheet.getRange(8, CONFIG.COLS.FINAL_NUDGE).setValue(d(2026, 4, 27));

  // ---- TRACK 3 (WARM REFERRAL) SCENARIOS ----

  // CP-PROS-007 (row 9) — Track 3, just escalated, no warm actions yet
  // Expected: AO = "W1: Send warm referral email", AP = TODAY, AQ = TODAY
  // (Cold history preserved in S-Y)
  sheet.getRange(9, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 5));
  sheet.getRange(9, CONFIG.COLS.CONNECT_ACCEPTED).setValue('N');
  sheet.getRange(9, CONFIG.COLS.EMAIL_1).setValue(d(2026, 4, 9));
  sheet.getRange(9, CONFIG.COLS.EMAIL_2).setValue(d(2026, 4, 12));
  sheet.getRange(9, CONFIG.COLS.FOLLOWUP).setValue(d(2026, 4, 16));
  sheet.getRange(9, CONFIG.COLS.FINAL_NUDGE).setValue(d(2026, 4, 22));

  // CP-PROS-008 (row 10) — Track 3, warm email 1 sent, follow-up due
  // Expected: AO = "W2: Send warm follow-up email", AP = 01-May, AQ = OVERDUE
  sheet.getRange(10, CONFIG.COLS.WARM_EMAIL_1).setValue(d(2026, 4, 28));

  // CP-PROS-009 (row 11) — Track 3, warm sequence complete, ready to escalate
  // Expected: AO = "ESCALATE — Change Track to 4", AP = TODAY, AR = Needs escalation
  sheet.getRange(11, CONFIG.COLS.WARM_EMAIL_1).setValue(d(2026, 4, 15));
  sheet.getRange(11, CONFIG.COLS.WARM_FOLLOWUP).setValue(d(2026, 4, 18));
  sheet.getRange(11, CONFIG.COLS.WARM_PHONE).setValue(d(2026, 4, 22));

  // ---- TRACK 4 (FOUNDER CLOSE) SCENARIOS ----

  // CP-PROS-010 (row 12) — Track 4, just escalated, no founder actions yet
  // Expected: AO = "F1: Founder personal email (Pradeep sends)", AP = TODAY
  // (Cold + warm history preserved)

  // CP-PROS-011 (row 13) — Track 4, founder email sent, follow-up due
  // Expected: AO = "F2: Founder follow-up email", AP = 07-May, AQ = FUTURE
  sheet.getRange(13, CONFIG.COLS.FOUNDER_EMAIL_1).setValue(d(2026, 5, 1));

  // CP-PROS-012 (row 14) — Track 4, SEQUENCE COMPLETE (all 3 phases exhausted)
  // Expected: AO = "SEQUENCE COMPLETE", AR = Sequence complete
  sheet.getRange(14, CONFIG.COLS.FOUNDER_EMAIL_1).setValue(d(2026, 4, 10));
  sheet.getRange(14, CONFIG.COLS.FOUNDER_FOLLOWUP).setValue(d(2026, 4, 16));
  sheet.getRange(14, CONFIG.COLS.FOUNDER_FINAL).setValue(d(2026, 4, 23));

  // ---- EDGE CASE SCENARIOS ----

  // CP-PROS-013 (row 15) — Track 4, HALTED
  // Expected: AO = "PARKED", AR = Parked
  sheet.getRange(15, CONFIG.COLS.HALT).setValue('Y');

  // CP-PROS-014 (row 16) — Track 3, REPLIED during warm phase
  // Expected: AO = "REPLIED — handle manually", AR = Replied
  sheet.getRange(16, CONFIG.COLS.WARM_EMAIL_1).setValue(d(2026, 4, 25));
  sheet.getRange(16, CONFIG.COLS.REPLIED).setValue('Y');
  sheet.getRange(16, CONFIG.COLS.REPLY_CHANNEL).setValue('Email');

  // CP-PROS-015 (row 17) — Track 2, REPLIED during cold phase
  // Expected: AO = "REPLIED — handle manually", P = "Replied"
  sheet.getRange(17, CONFIG.COLS.CONNECT_SENT).setValue(d(2026, 4, 15));
  sheet.getRange(17, CONFIG.COLS.CONNECT_ACCEPTED).setValue('Y');
  sheet.getRange(17, CONFIG.COLS.FIRST_MESSAGE).setValue(d(2026, 4, 17));
  sheet.getRange(17, CONFIG.COLS.REPLIED).setValue('Y');
  sheet.getRange(17, CONFIG.COLS.REPLY_CHANNEL).setValue('LinkedIn');

  SpreadsheetApp.flush();

  ui.alert(
    'Test Scenarios Loaded (v4)',
    'Rows 5-17 now have test data covering all 4 tracks + escalation + edge cases.\n\n' +
    'Check columns AO (Next Action), AP (Next Action Date), AQ (Action Due?), and AR (Status).\n' +
    'Also check P (Current Stage) — should show full escalation pipeline stages.\n\n' +
    'Key scenarios to verify:\n' +
    '  Row 8: Cold complete → ESCALATE to Track 3\n' +
    '  Row 9: Track 3 just escalated → W1 due today\n' +
    '  Row 11: Warm complete → ESCALATE to Track 4\n' +
    '  Row 14: All 3 phases done → SEQUENCE COMPLETE',
    ui.ButtonSet.OK
  );
}


// =====================================================================
// WEB APP — AUTO-STAMP ENDPOINT (doPost)
// =====================================================================
//
// Enables external tools (Cowork reconciliation task) to stamp dates and
// update dropdowns in the sheet without manual intervention.
//
// DEPLOY:
//   1. In Apps Script editor: Deploy -> New deployment
//   2. Type: Web app
//   3. Execute as: Me (jhalak.wadhwa@agresearchlabs.com)
//   4. Who has access: Anyone with the link
//   5. Copy the deployment URL — give it to the Cowork task
//
// REQUEST FORMAT (POST, JSON body):
//
//   {
//     "secret": "<shared passphrase>",
//     "updates": [
//       { "prospectId": "CP-PROS-003", "column": "V", "value": "2026-05-04" },
//       { "prospectId": "CP-PROS-007", "column": "AK", "value": "Y" }
//     ]
//   }
//
// RESPONSE: { "status": "ok", "applied": 2, "errors": [] }
//
// Supported columns for date stamps:
//   Cold: S, T, U, V, W, X, Y
//   Warm: Z, AA, AB
//   Founder: AC, AD, AE
//   Conversion: AG (Call Date)
// Supported columns for dropdowns: AJ, AK, AL, AM, AH (Deal Stage)
//
// Security: a shared secret prevents unauthorized writes. Set it in
// Script Properties: File -> Project properties -> Script properties ->
// Add: key = "STAMP_SECRET", value = <your passphrase>

var STAMP_SECRET_KEY = 'STAMP_SECRET';

// Column letter -> CONFIG.COLS number mapping for allowed stamp targets
var STAMP_COL_MAP = {
  'S':  19, 'T':  20, 'U':  21, 'V':  22, 'W':  23,
  'X':  24, 'Y':  25, 'Z':  26, 'AA': 27, 'AB': 28,
  'AC': 29, 'AD': 30, 'AE': 31, 'AG': 33,
  'AH': 34, 'AJ': 36, 'AK': 37, 'AL': 38, 'AM': 39
};

// Columns that accept dates vs dropdown values
var DATE_COLS = ['S','T','U','V','W','X','Y','Z','AA','AB','AC','AD','AE','AG'];
var DROPDOWN_COLS = ['AH','AJ','AK','AL','AM'];

function doPost(e) {
  try {
    var payload = JSON.parse(e.postData.contents);

    // --- Auth check ---
    var expectedSecret = PropertiesService.getScriptProperties().getProperty(STAMP_SECRET_KEY);
    if (expectedSecret && payload.secret !== expectedSecret) {
      return ContentService.createTextOutput(
        JSON.stringify({ status: 'error', message: 'Invalid secret' })
      ).setMimeType(ContentService.MimeType.JSON);
    }

    var updates = payload.updates || [];
    if (!updates.length) {
      return ContentService.createTextOutput(
        JSON.stringify({ status: 'error', message: 'No updates provided' })
      ).setMimeType(ContentService.MimeType.JSON);
    }

    var sheet = getSheet_();
    var lastRow = Math.min(sheet.getLastRow(), CONFIG.MAX_ROW);

    // Build prospect ID -> row number lookup
    var idRange = sheet.getRange(CONFIG.DATA_START_ROW, CONFIG.COLS.PROSPECT_ID,
                                  lastRow - CONFIG.DATA_START_ROW + 1, 1).getValues();
    var idToRow = {};
    for (var i = 0; i < idRange.length; i++) {
      var id = String(idRange[i][0]).trim();
      if (id) idToRow[id] = CONFIG.DATA_START_ROW + i;
    }

    var applied = 0;
    var errors = [];

    updates.forEach(function(upd, idx) {
      var pid = String(upd.prospectId || '').trim();
      var col = String(upd.column || '').trim().toUpperCase();
      var val = upd.value;

      // Validate prospect ID
      if (!idToRow[pid]) {
        errors.push('Update ' + idx + ': prospect "' + pid + '" not found');
        return;
      }

      // Validate column
      if (!STAMP_COL_MAP[col]) {
        errors.push('Update ' + idx + ': column "' + col + '" not allowed');
        return;
      }

      var row = idToRow[pid];
      var colNum = STAMP_COL_MAP[col];
      var cell = sheet.getRange(row, colNum);

      if (DATE_COLS.indexOf(col) >= 0) {
        // Parse and set date
        var dateVal = new Date(val);
        if (isNaN(dateVal.getTime())) {
          errors.push('Update ' + idx + ': invalid date "' + val + '"');
          return;
        }
        cell.setValue(dateVal);
      } else if (DROPDOWN_COLS.indexOf(col) >= 0) {
        // Set dropdown value directly
        cell.setValue(String(val));
      }

      applied++;
    });

    SpreadsheetApp.flush();

    return ContentService.createTextOutput(
      JSON.stringify({ status: 'ok', applied: applied, errors: errors })
    ).setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(
      JSON.stringify({ status: 'error', message: err.toString() })
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

// GET handler — returns sheet status summary (useful for health checks)
function doGet(e) {
  try {
    var sheet = getSheet_();
    var lastRow = Math.min(sheet.getLastRow(), CONFIG.MAX_ROW);
    var numProspects = 0;
    var ids = sheet.getRange(CONFIG.DATA_START_ROW, 1, lastRow - CONFIG.DATA_START_ROW + 1, 1).getValues();
    ids.forEach(function(r) { if (r[0]) numProspects++; });

    return ContentService.createTextOutput(
      JSON.stringify({
        status: 'ok',
        sheet: CONFIG.SHEET_NAME,
        prospects: numProspects,
        formulaRows: CONFIG.DATA_START_ROW + '-' + CONFIG.MAX_ROW
      })
    ).setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(
      JSON.stringify({ status: 'error', message: err.toString() })
    ).setMimeType(ContentService.MimeType.JSON);
  }
}
