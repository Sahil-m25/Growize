import 'package:flutter/material.dart';

import 'package:arl_app/core/theme/arl_colors.dart';

/// Sand-coloured rounded placeholder used as the universal "no data yet"
/// stand-in across screens.
///
/// Renders for both the loading state and the error fallback so the UI
/// is never blank — repos already cache successful responses, so a
/// skeleton only shows on a true cold start with no cache (or while a
/// refetch is in flight without prior data).
class SkelBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  final EdgeInsets margin;

  const SkelBox({
    required this.height,
    this.width,
    this.radius = 12,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
