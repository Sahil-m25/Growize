# Jev field-mapping check — 2026-09-26

Model: jev-1.13.0. 158 Supabase field reads in lib/ checked against the live schema (70 baseline).
Exact-name reads got a Noul "does this column mean what the app uses it for"; reads with no matching column got a Choice among the file's live columns + none/derived.

Run again: `export TYPESAFE_API_KEY=...` then `python3 extract.py && python3 jev.py` (key is read from the environment only; never commit it).

| Where | Read | Jev | Verdict |
|---|---|---|---|
| investor_unit.dart:49 | `capital_outstanding` | fit 0.79 | OK. |
| marketplace_project.dart:47 | `crop_type` -> cropType | -> none (0.70) | CONFIRMED - crop_type has no live column. Removed. |
| marketplace_project.dart:58 | `status` -> llpStatus | fit 0.75 | NAMING ONLY - projects.status stored as llpStatus; not displayed. |
| project_phase.dart:29 | `name` -> name | -> project_phases.phase_name (0.97) | OK - legacy fallback after phase_name. |
| project_phase.dart:32 | `phase_date` | fit 0.74 | OK - phase_date is the milestone date. |
| project_phase.dart:33 | `start_date` | -> project_phases.phase_date (0.58) | OK - legacy fallback after phase_date. |
| project_phase.dart:36 | `started_at` -> startedAt | -> none (0.45) | OK - optional, always null; UI uses phase_date. |
| project_phase.dart:37 | `started_at` | -> none (0.71) | OK - same. |
| project_phase.dart:39 | `completed_at` -> completedAt | -> none (0.66) | OK - optional, always null. |
| project_phase.dart:40 | `completed_at` | -> project_phases.sort_order (0.86) | JEV WRONG (picked sort_order); correct answer is none. Harmless. |
| project.dart:70 | `updated_at` | fit 0.26 | CONFIRMED - updated_at used as contract start; "Month X/60" reset on every sync. Fixed. |
| project.dart:85 | `tier` -> cropType | fit 0.12 | CONFIRMED - tier used as cropType. Crop UI removed; field only feeds the tier badge now. |
| project.dart:91 | `total_ticket_size` -> investedAmount | fit 0.50 | CONFIRMED - project ticket size summed as the investor's own investment (selector fallback). Fixed. |
| kyc_screen.dart:70 | `created_at` | -> investors.onboarded_at (0.58) | CONFIRMED - created_at does not exist. Jev picked onboarded_at (0.59) over kyc_submitted_at (0.34); human override: kyc_submitted_at is "Submitted on". Fixed with onboarded_at fallback. |
| portfolio_summary.dart:70 | `next_payout_date` | fit 0.61 | CONFIRMED - null next_payout_date replaced with now()+30 days (invented date). Fixed. |
| project_document.dart:61 | `uploaded_at` | fit 0.72 | OK - uploaded_at as display date. |
| gallery_photo.dart:30 | `taken_at` | fit 0.79 | OK. |
| ticket_detail_screen.dart:234 | `created_at` | fit 0.41 | FALSE ALARM - extractor attached the wrong table; msg[] is ticket_messages.created_at. |
| exit_screen.dart:47 | `id` | fit 0.77 | OK - id passed as investor_unit_id. |
| financials_repository.dart:108 | `_project_name` | -> projects.name (0.78) | OK - synthetic key set by the app. |

All other 138 reads scored fit >= 0.80 and matched on review.
