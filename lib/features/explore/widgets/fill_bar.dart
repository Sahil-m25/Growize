import 'package:flutter/material.dart';

import 'package:arl_app/core/theme/arl_colors.dart';

/// Reusable horizontal fill bar used in marketplace tiles and the
/// marketplace detail "Units Available" stat card. Colour ramps from
/// accent (≤70%) → gold (70-90%) → earth (≥90%) as a project fills up.
///
/// `compact: true` (the default in tiles) renders a 6px height bar;
/// otherwise renders a slightly taller 8px bar for the detail screen.
class FillBar extends StatelessWidget {
  final int filled;
  final int total;
  final bool compact;

  const FillBar({
    required this.filled,
    required this.total,
    this.compact = true,
    super.key,
  });

  /// Pick the fill colour based on percentage filled.
  /// ≤70%: accent. 70-90%: gold. ≥90%: earth.
  static Color colourFor(double pct) {
    if (pct >= 0.9) return ArlColors.earth;
    if (pct >= 0.7) return ArlColors.gold;
    return ArlColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1 : total;
    final pct = (filled / safeTotal).clamp(0.0, 1.0);
    final height = compact ? 6.0 : 8.0;
    final radius = compact ? 3.0 : 4.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: pct,
        minHeight: height,
        backgroundColor: ArlColors.sand,
        valueColor: AlwaysStoppedAnimation<Color>(colourFor(pct)),
      ),
    );
  }
}
