import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/theme/arl_colors.dart';

/// QA preview tile for the first-payout celebration overlay.
///
/// T4 will drop this into Profile → Settings (or a debug menu) so the
/// team can re-enter the celebration without resetting Hive. The route
/// is pushed with hard-coded sample data (₹41,000 from EKA on
/// Mar 15, 2026) and does NOT toggle [CelebrationFlag] — it's a preview,
/// not a "real" first-payout event.
class CelebrationPreviewEntry extends StatelessWidget {
  const CelebrationPreviewEntry({super.key});

  static const String _previewRoute =
      '/celebration?amount=41000&project=EKA&date=2026-03-15';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.celebration_outlined, color: ArlColors.gold),
      title: const Text(
        'Preview first-payout celebration',
        style: TextStyle(
          color: ArlColors.charcoal,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'Opens the overlay with sample data',
        style: TextStyle(color: ArlColors.muted, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: ArlColors.muted,
        size: 20,
      ),
      onTap: () => context.push(_previewRoute),
    );
  }
}
