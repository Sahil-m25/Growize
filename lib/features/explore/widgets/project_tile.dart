import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/explore/widgets/fill_bar.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';

/// Marketplace tile rendered in the Explore grid. Maps directly to a
/// `MarketplaceProject` row. Tap routes to `/explore/<id>`.
///
/// Visual reference: tile blocks in `page-explore` of the v2 mockup —
/// 16:10 hero with status pill overlay; body has name, location, crop
/// chip, fill bar with `X / Y units` label (or the "Fully subscribed"
/// pill when sold out), and price per unit bottom-right.
class ProjectTile extends StatelessWidget {
  final MarketplaceProject project;

  const ProjectTile({required this.project, super.key});

  @override
  Widget build(BuildContext context) {
    final pricePerUnitText = _formatPricePerUnit(project.pricePerUnit);
    // Wrap in Material so the InkWell splash + hit detection works
    // reliably on Flutter web. Without an explicit Material ancestor,
    // the InkWell's tap routing depends on whatever ambient Material
    // happens to be above — fragile inside a CustomScrollView/Stack.
    // GestureDetector with HitTestBehavior.opaque guarantees the tap is
    // caught even if the inner Container paints opaque pixels over the
    // tile area — previous Material→InkWell→Container nesting was
    // silently swallowing taps on some Flutter web builds.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/explore/${project.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: ArlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ArlColors.sand),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  if (project.location.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 11,
                          color: ArlColors.muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            project.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ArlColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // DEF-V32-AUTH-05: always render a crop chip — fall
                  // back to "Mixed crops" when the project row has no
                  // crop_type set, so tiles never lose their identity
                  // strip on seed data.
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _cropChip(
                      (project.cropType != null &&
                              project.cropType!.isNotEmpty)
                          ? project.cropType!
                          : 'Mixed crops',
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Two pill stats: Total Units · Area in acres.
                  _statPillsRow(),
                  const SizedBox(height: 8),
                  // Remaining units strip with sold-portion progress bar.
                  _remainingSection(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        pricePerUnitText,
                        style: const TextStyle(
                          color: ArlColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: ArlColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero (16:9-ish — using 16:10 to match the mockup's aspect-[16/10]).
  Widget _hero() {
    final img = project.marketplaceImage;
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (img != null && img.isNotEmpty)
            CachedNetworkImage(
              imageUrl: img,
              fit: BoxFit.cover,
              placeholder: (_, __) => _heroFallback(),
              errorWidget: (_, __, ___) => _heroFallback(),
            )
          else
            _heroFallback(),
          Positioned(top: 8, left: 8, child: _statusPill()),
        ],
      ),
    );
  }

  // DEF-V32-AUTH-05: when `marketplace_image` is null on the row (very
  // common on seed/dev data), the previous fallback was just a leaf
  // icon on a sand background — visually identical for every tile.
  // The new fallback paints a deterministic primary→accent gradient
  // keyed off the project id and overlays the project's initial, so
  // tiles still feel distinct without a hero photo.
  Widget _heroFallback() {
    final initial = project.name.trim().isNotEmpty
        ? project.name.trim()[0].toUpperCase()
        : '?';
    // Pick a deterministic accent tint from the project id so each
    // tile keeps a stable identity across rebuilds.
    final tints = <Color>[
      ArlColors.primary,
      ArlColors.accent,
      ArlColors.gold,
      ArlColors.earth,
    ];
    final tint = tints[project.id.hashCode.abs() % tints.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tint.withOpacity(0.85),
            ArlColors.accent.withOpacity(0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 8,
            child: Icon(
              Icons.eco_outlined,
              color: Colors.white70,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ── Status pill derived from the marketplace_project flags.
  Widget _statusPill() {
    final spec = _StatusPillSpec.forProject(project);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.leadingIcon != null) ...[
            Icon(spec.leadingIcon, color: spec.fg, size: 10),
            const SizedBox(width: 3),
          ],
          Text(
            spec.label,
            style: TextStyle(
              color: spec.fg,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cropChip(String crop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ArlColors.sand,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        crop,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Row of two compact pill stats: Total Units · Area in acres.
  //
  // Replaces the old "Units Available" line in the tile body per the
  // 2026-05-21 redesign. Falls back to "—" when the row is missing the
  // underlying figure (e.g. acreage_acres is null on demo projects).
  Widget _statPillsRow() {
    final totalLabel = project.totalUnits > 0
        ? '${project.totalUnits} units total'
        : '—';
    final acres = project.acreageAcres;
    final acresLabel = (acres != null && acres > 0)
        ? _formatAcres(acres)
        : '—';
    return Row(
      children: [
        Expanded(
          child: _miniStatPill(
            icon: Icons.grid_view_outlined,
            text: totalLabel,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _miniStatPill(
            icon: Icons.crop_square,
            text: acresLabel,
          ),
        ),
      ],
    );
  }

  Widget _miniStatPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: ArlColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Remaining-units strip with sold-portion progress bar.
  //
  // Sold-out and coming-soon projects show their existing dedicated
  // pills (kept verbatim from the previous fill section). Otherwise we
  // render "Remaining: X of Y" with a thin bar whose filled portion =
  // sold units (accent green) and empty portion = available (sand).
  Widget _remainingSection() {
    final total = project.totalUnits;
    final available = project.unitsAvailable;
    final sold = (total - available).clamp(0, total);

    if (total > 0 && available == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: ArlColors.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ArlColors.accent.withOpacity(0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 12, color: ArlColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$total/$total · Fully subscribed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ArlColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (project.isComingSoon) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FillBar(filled: 0, total: total == 0 ? 1 : total),
          const SizedBox(height: 4),
          Text(
            _comingSoonLabel(),
            style: const TextStyle(color: ArlColors.muted, fontSize: 10),
          ),
        ],
      );
    }

    final denom = total == 0 ? 1 : total;
    final filledFraction = (sold / denom).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 11, color: ArlColors.muted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$available of $total remaining',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(filledFraction * 100).round()}% sold',
              style: const TextStyle(
                color: ArlColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 5,
            color: ArlColors.sand,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: filledFraction,
                child: Container(color: ArlColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatAcres(double acres) {
    // One decimal for partial acres, integer for whole acres.
    if (acres == acres.truncate()) {
      return '${acres.toStringAsFixed(0)} acres';
    }
    return '${acres.toStringAsFixed(1)} acres';
  }

  String _comingSoonLabel() {
    final deadline = project.subscriptionDeadline;
    if (deadline != null) {
      final fmt = DateFormat('MMM y').format(deadline);
      return 'Reservations open $fmt';
    }
    return 'Reservations open soon';
  }

  static String _formatPricePerUnit(double pricePerUnit) {
    if (pricePerUnit <= 0) return '—';
    final lakhs = pricePerUnit / 100000;
    final fmt = NumberFormat('#,##,##0.##', 'en_IN');
    return '₹${fmt.format(lakhs)} L/unit';
  }
}

/// Status-pill colour/label/icon, derived from MarketplaceProject flags.
class _StatusPillSpec {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? leadingIcon;

  const _StatusPillSpec({
    required this.label,
    required this.bg,
    required this.fg,
    this.leadingIcon,
  });

  factory _StatusPillSpec.forProject(MarketplaceProject p) {
    // SOLD OUT: total > 0 and none remaining. Uses accent + check icon.
    if (p.totalUnits > 0 && p.unitsAvailable == 0) {
      return const _StatusPillSpec(
        label: 'SOLD OUT',
        bg: ArlColors.accent,
        fg: Colors.white,
        leadingIcon: Icons.check_circle,
      );
    }
    if (p.isComingSoon) {
      return const _StatusPillSpec(
        label: 'COMING SOON',
        bg: ArlColors.primary,
        fg: Colors.white,
      );
    }
    if (p.isOpenForReservation) {
      return const _StatusPillSpec(
        label: 'OPEN',
        bg: ArlColors.accent,
        fg: Colors.white,
      );
    }
    if (p.isClosed) {
      return _StatusPillSpec(
        label: 'CLOSED',
        bg: ArlColors.earth.withOpacity(0.85),
        fg: Colors.white,
      );
    }
    // Fallback — treat unknown states as OPEN.
    return const _StatusPillSpec(
      label: 'OPEN',
      bg: ArlColors.accent,
      fg: Colors.white,
    );
  }
}
