import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/arl_colors.dart';

/// Per-stage date pair fed into [PhaseTimeline6]. A 10-element list
/// (one slot per stage 1..10) is passed alongside `currentStageIndex`;
/// `null` entries render with no date affordance.
///
/// * `startedAt`   — when work on the stage began. Used for the
///                   "In progress — started <date>" line on the
///                   current node's bottom-sheet detail.
/// * `completedAt` — when the stage was signed off. Used for the
///                   "Completed <date>" line on done nodes plus the
///                   tiny date label rendered under the node label.
class PhaseStageDates {
  final DateTime? startedAt;
  final DateTime? completedAt;

  const PhaseStageDates({this.startedAt, this.completedAt});

  bool get isEmpty => startedAt == null && completedAt == null;
}

/// Fixed 10-stage roadmap timeline matching the Zoho project-phases
/// taxonomy. Stages 1-10 (in the same order as the v3 mockup):
///
///   1.  Land Closed
///   2.  Design & Plan Locked
///   3.  Site Prep
///   4.  Core Civil
///   5.  Procurement Locked
///   6.  Water Source & Storage Ready
///   7.  Power Ready
///   8.  Greenhouse
///   9.  Production Systems Installed
///   10. Compliance Closed + Go-live
///
/// Rendered as a two-row "snake" roadmap so the timeline reads big on
/// narrow phones instead of being squashed into one cramped strip:
///
/// ```
///   [1]──[2]──[3]──[4]──[5]
///                         │
///                         ▼
///   [10]─[9]──[8]──[7]──[6]
/// ```
///
/// Each node is 40 px in diameter with the stage number / check mark
/// inside, and the short label sits directly under it. Tapping a node
/// opens a bottom sheet with the full stage label and its status
/// (Completed / In progress / Upcoming) — plus, when [phaseDates] is
/// provided, a date line:
///   * Done    → "Completed 12 Mar 2026"
///   * Current → "In progress — started 5 May 2026"
///   * Pending → "Upcoming"
///
/// Done nodes also get a tiny date label (e.g. "12 Mar") rendered
/// directly under the existing stage label so the timeline visually
/// communicates *when* progress happened, not just *that* it did.
///
/// Node colours:
///   * Done    → filled gold disc
///   * Current → outlined primary disc (white fill, primary ring)
///   * Pending → outlined muted disc  (white fill, muted ring)
///
/// Class name kept as `PhaseTimeline6` for source-stability — it now
/// renders 10 stages, but all existing call sites just need to pass the
/// `currentStageIndex` and the widget reads the new label list.
class PhaseTimeline6 extends StatelessWidget {
  /// 0-based index of the active stage (0..9). Clamped on read.
  final int currentStageIndex;

  /// Optional override colour for the "current" stage ring. Defaults to
  /// `ArlColors.primary` — Sunrise Orchards passes its brown tint here
  /// so the current stage matches the rest of the project theme.
  final Color? accentOverride;

  /// Optional per-stage started/completed timestamps. Should be a 10-
  /// element list — one slot per stage in stage order (0..9). Shorter
  /// lists are padded with nulls; longer lists are truncated.
  ///
  /// When null is passed the widget behaves exactly like the original
  /// (no date labels rendered) — keeps the demo / legacy code path
  /// unchanged.
  final List<PhaseStageDates?>? phaseDates;

  const PhaseTimeline6({
    super.key,
    required this.currentStageIndex,
    this.accentOverride,
    this.phaseDates,
  });

  /// Compact labels printed under each dot.
  static const _labels = <String>[
    'Land',
    'Design',
    'Site',
    'Civil',
    'Procure',
    'Water',
    'Power',
    'Greenhouse',
    'Systems',
    'Go-live',
  ];

  /// Full labels used in headers / current-phase pills.
  static const _fullLabels = <String>[
    'Land Closed',
    'Design & Plan Locked',
    'Site Prep',
    'Core Civil',
    'Procurement Locked',
    'Water Source & Storage Ready',
    'Power Ready',
    'Greenhouse',
    'Production Systems Installed',
    'Compliance Closed + Go-live',
  ];

  /// Total stage count — exposed so callers can render "Stage N of X"
  /// without hard-coding the magic number.
  static const stageCount = 10;

  /// Normalised lookup that handles null / short / long input lists
  /// without crashing the widget tree.
  PhaseStageDates? _datesFor(int idx) {
    final src = phaseDates;
    if (src == null) return null;
    if (idx < 0 || idx >= src.length) return null;
    return src[idx];
  }

  @override
  Widget build(BuildContext context) {
    final clamped = currentStageIndex.clamp(0, stageCount - 1);
    final accent = accentOverride ?? ArlColors.primary;

    // Row 1 = stages 0..4 left-to-right.
    final row1 = List<int>.generate(5, (i) => i);
    // Row 2 = stages 9..5 (rendered right-to-left so the flow snakes
    // down from stage 5 → stage 6 on the right edge of the lower row).
    final row2 = List<int>.generate(5, (i) => 9 - i);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        // Reserve room for 5 nodes + 4 connectors per row. Compact
        // node size: 28-32px (was 36-48px) to keep the whole "Current
        // Phase" card under ~220px tall on mobile.
        final perStage = (maxW / 5).clamp(56.0, 110.0);
        final nodeSize = (perStage * 0.40).clamp(28.0, 32.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoadmapRow(
              stageIndices: row1,
              currentIndex: clamped,
              accent: accent,
              nodeSize: nodeSize,
              datesFor: _datesFor,
              onNodeTap: (idx) => _showStageDetail(context, idx, clamped),
            ),
            // Single tight chevron between the two rows (replaces the
            // longer line + arrow that was inflating vertical height).
            _RoadmapConnector(
              alignRight: true,
              nodeSize: nodeSize,
              colour: clamped >= 5
                  ? ArlColors.gold
                  : ArlColors.muted.withValues(alpha: 0.4),
            ),
            _RoadmapRow(
              stageIndices: row2,
              currentIndex: clamped,
              accent: accent,
              nodeSize: nodeSize,
              datesFor: _datesFor,
              onNodeTap: (idx) => _showStageDetail(context, idx, clamped),
            ),
          ],
        );
      },
    );
  }

  void _showStageDetail(BuildContext context, int idx, int currentIdx) {
    final status = idx < currentIdx
        ? 'Completed'
        : idx == currentIdx
            ? 'In progress'
            : 'Upcoming';
    final statusColor = idx < currentIdx
        ? ArlColors.gold
        : idx == currentIdx
            ? ArlColors.primary
            : ArlColors.muted;

    final dates = _datesFor(idx);
    String? dateLine;
    if (idx < currentIdx) {
      final on = dates?.completedAt;
      if (on != null) dateLine = 'Completed on ${_formatLong(on)}';
    } else if (idx == currentIdx) {
      final on = dates?.startedAt;
      if (on != null) {
        dateLine = 'In progress — started ${_formatLong(on)}';
      }
    }
    // Upcoming stages render the existing status pill only — no extra
    // date line ("Upcoming" alone is the clearer signal).

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ArlColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ArlColors.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Stage ${idx + 1} of $stageCount',
                style: const TextStyle(
                  color: ArlColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fullLabels[idx],
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      idx < currentIdx
                          ? Icons.check_circle
                          : idx == currentIdx
                              ? Icons.adjust
                              : Icons.schedule,
                      size: 13,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (dateLine != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 14, color: ArlColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateLine,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// "12 Mar 2026" — used in the bottom-sheet detail line.
  static String _formatLong(DateTime d) =>
      DateFormat('d MMM yyyy').format(d);

  /// "12 Mar" (no year, same-year omitted) — used for the tiny date
  /// label under each completed node so the row height stays tight.
  /// Year is appended only when it differs from the current calendar
  /// year, so cross-year completions remain unambiguous.
  static String _formatShort(DateTime d) {
    final thisYear = DateTime.now().year;
    if (d.year == thisYear) return DateFormat('d MMM').format(d);
    return DateFormat('d MMM yy').format(d);
  }

  /// Convenience: returns the full label for a given stage index — used
  /// by the detail screen to render the "Current Phase: <name>" pill.
  static String labelAt(int index) =>
      _fullLabels[index.clamp(0, stageCount - 1)];
}

/// One row of the roadmap — five evenly-spaced nodes with connector
/// segments between them. Status colours are driven by [currentIndex]:
/// nodes with `stageIndex < currentIndex` render as done (gold filled),
/// equal to it as current (primary ring), greater than it as pending
/// (muted ring).
class _RoadmapRow extends StatelessWidget {
  final List<int> stageIndices;
  final int currentIndex;
  final Color accent;
  final double nodeSize;
  final PhaseStageDates? Function(int stageIndex) datesFor;
  final void Function(int stageIndex) onNodeTap;

  const _RoadmapRow({
    required this.stageIndices,
    required this.currentIndex,
    required this.accent,
    required this.nodeSize,
    required this.datesFor,
    required this.onNodeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(stageIndices.length, (i) {
        final stageIdx = stageIndices[i];
        final isDone = stageIdx < currentIndex;
        final isCurrent = stageIdx == currentIndex;
        // The connector segment to the right of this node hugs the
        // logical "flow" direction. For row 1 (LTR), the segment
        // connects stageIdx → stageIdx+1. For row 2 (RTL), it connects
        // stageIdx → stageIdx-1. Either way we want the segment "done"
        // when the higher of the two indices has been reached.
        final isLastInRow = i == stageIndices.length - 1;
        bool segmentDone = false;
        if (!isLastInRow) {
          final nextStage = stageIndices[i + 1];
          final higher = stageIdx > nextStage ? stageIdx : nextStage;
          segmentDone = currentIndex > higher;
        }

        return Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoadmapNode(
                stageIndex: stageIdx,
                isDone: isDone,
                isCurrent: isCurrent,
                accent: accent,
                size: nodeSize,
                label: PhaseTimeline6._labels[stageIdx],
                dates: datesFor(stageIdx),
                onTap: () => onNodeTap(stageIdx),
              ),
              if (!isLastInRow)
                Expanded(
                  child: Padding(
                    // Align the connector with the node disc (top half
                    // of the node column) so adding the date sub-label
                    // below the node doesn't pull the line downward.
                    padding: EdgeInsets.only(top: nodeSize / 2 - 1),
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: segmentDone
                            ? ArlColors.gold.withValues(alpha: 0.7)
                            : ArlColors.muted.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// A single stage node + label (+ optional 8pt date sub-label).
class _RoadmapNode extends StatelessWidget {
  final int stageIndex;
  final bool isDone;
  final bool isCurrent;
  final Color accent;
  final double size;
  final String label;
  final PhaseStageDates? dates;
  final VoidCallback onTap;

  const _RoadmapNode({
    required this.stageIndex,
    required this.isDone,
    required this.isCurrent,
    required this.accent,
    required this.size,
    required this.label,
    required this.dates,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color borderColor;
    final Color fgColor;
    if (isDone) {
      bgColor = ArlColors.gold;
      borderColor = ArlColors.gold;
      fgColor = Colors.white;
    } else if (isCurrent) {
      bgColor = Colors.white;
      borderColor = accent;
      fgColor = accent;
    } else {
      bgColor = Colors.white;
      borderColor = ArlColors.muted.withValues(alpha: 0.45);
      fgColor = ArlColors.muted;
    }

    // Sub-label under the existing stage label:
    //   * Done    → tiny "12 Mar" (omit year if same as this year)
    //   * Current → italic "(in progress)"
    //   * Pending → nothing (keeps the row visually tight)
    //
    // Gracefully renders nothing when no date is present on a done
    // node, so seeded-but-incomplete rows don't show "null" or empty.
    String? subLabel;
    bool subLabelItalic = false;
    if (isDone) {
      final on = dates?.completedAt;
      if (on != null) subLabel = PhaseTimeline6._formatShort(on);
    } else if (isCurrent) {
      subLabel = '(in progress)';
      subLabelItalic = true;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: isCurrent ? 2 : 1.4,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: isDone
                    ? Icon(Icons.check, size: size * 0.46, color: fgColor)
                    : Text(
                        '${stageIndex + 1}',
                        style: TextStyle(
                          color: fgColor,
                          fontSize: size * 0.36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: size + 14,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? accent : ArlColors.muted,
                    fontSize: 9,
                    fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (subLabel != null)
                SizedBox(
                  width: size + 18,
                  child: Text(
                    subLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ArlColors.muted,
                      fontSize: 8,
                      fontStyle: subLabelItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tight single-chevron connector that joins the two roadmap rows so
/// the eye flows from stage 5 → stage 6 down on the right edge. The
/// previous variant had a 14px vertical line + 18px chevron (~36px
/// total with padding); this compact version uses a single 14px
/// chevron with 2px of vertical breathing room.
class _RoadmapConnector extends StatelessWidget {
  final bool alignRight;
  final double nodeSize;
  final Color colour;

  const _RoadmapConnector({
    required this.alignRight,
    required this.nodeSize,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    // Centre of the last node in row 1 sits `nodeSize / 2` from the
    // right edge — the chevron lines up with it.
    final padding = nodeSize / 2 - 1;
    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        right: alignRight ? padding : 0,
        left: alignRight ? 0 : padding,
      ),
      child: Row(
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Icon(Icons.keyboard_arrow_down, size: 14, color: colour),
        ],
      ),
    );
  }
}
