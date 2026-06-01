import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/arl_colors.dart';

/// Two big CTA tiles in a row — `View Area` / `Photos`.
///
/// Mirrors the v3 R5 "2 CTA tiles" block in the HTML — the Documents
/// tile was explicitly removed because Documents is a top-level tab,
/// not project-scoped (HTML comment: `R5: 2 CTA tiles (Documents tile
/// removed)`). Investors get to documents via the bottom-nav Documents
/// tab.
///
/// Each tile is a white rounded card with an icon disc, a label, and a
/// small caption. Tapping pushes the corresponding route under
/// `/projects/<id>/...`.
class ProjectActionTiles extends StatelessWidget {
  final String projectId;

  /// When true, the Photos tile renders dimmed and is non-tappable —
  /// matches the HTML "After setup" state on Verdant Acres.
  final bool photosLocked;

  /// Optional brand tint for the View Area icon disc. Falls back to
  /// arl-accent if null.
  final Color? viewAreaTint;

  const ProjectActionTiles({
    super.key,
    required this.projectId,
    this.photosLocked = false,
    this.viewAreaTint,
  });

  @override
  Widget build(BuildContext context) {
    final viewTint = viewAreaTint ?? ArlColors.accent;

    // IntrinsicHeight gives the Row a bounded cross-axis (vertical) so
    // `CrossAxisAlignment.stretch` works. Without it — at wide web
    // viewports where the parent SingleChildScrollView passes unbounded
    // vertical — the Row throws a RenderFlex "no size" exception
    // because stretch tries to size children to the row's height,
    // which is infinity.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Tile(
              icon: Icons.map_outlined,
              tint: viewTint,
              label: 'View Area',
              caption: 'Map · tech · crops',
              onTap: () => context.push('/projects/$projectId/view-area'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Tile(
              icon: Icons.photo_library_outlined,
              tint: photosLocked ? ArlColors.muted : ArlColors.primary,
              label: 'Photos',
              caption: photosLocked ? 'After setup' : 'Daily 9 AM IST',
              disabled: photosLocked,
              onTap: photosLocked
                  ? null
                  : () => context.push('/projects/$projectId/photos'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String caption;
  final VoidCallback? onTap;
  final bool disabled;

  const _Tile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.caption,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tint, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 10,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Opacity(opacity: disabled ? 0.6 : 1, child: card);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: card,
      ),
    );
  }
}
