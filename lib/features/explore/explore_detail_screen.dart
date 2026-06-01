import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/explore/widgets/share_project_modal.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Marketplace-mode project detail screen.
///
/// Visual reference: `page-explore-detail` in the v2 mockup. Fields not
/// available on `MarketplaceProject` (growing tech specs, photo strip,
/// nearby town) come from a per-project lookup table seeded with the six
/// projects wired up in the HTML — see [_ExploreDetailMock]. The lookup
/// is keyed by `MarketplaceProject.id`; when a real listing isn't in the
/// table we fall back to neutral defaults so the screen still renders.
class ExploreDetailScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ExploreDetailScreen({required this.projectId, super.key});

  @override
  ConsumerState<ExploreDetailScreen> createState() =>
      _ExploreDetailScreenState();
}

class _ExploreDetailScreenState extends ConsumerState<ExploreDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(marketplaceProjectsProvider);
    final project = async.valueOrNull?.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => _placeholder,
    );

    if (project == null) {
      // Cold start with no cache — show a lightweight loader.
      return _shell(child: const Center(child: CircularProgressIndicator()));
    }
    if (project.id.isEmpty) {
      return _shell(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Project not found.',
              style: TextStyle(color: ArlColors.muted),
            ),
          ),
        ),
      );
    }
    return _shell(child: _body(project), project: project);
  }

  // ── Shell with AppBar (back arrow + project title + share). ───────
  Widget _shell({required Widget child, MarketplaceProject? project}) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: ArlColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.explore);
            }
          },
        ),
        title: Text(
          project?.name ?? 'Project',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ArlColors.charcoal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (project != null)
            IconButton(
              tooltip: 'Share Project',
              icon: const Icon(Icons.share, color: ArlColors.charcoal),
              onPressed: () => _openShare(project),
            ),
        ],
      ),
      body: child,
    );
  }

  Widget _body(MarketplaceProject p) {
    final mock = _ExploreDetailMock.forProject(p);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroBanner(p, mock),
          const SizedBox(height: 16),
          _marketplaceStats(p),
          const SizedBox(height: 12),
          _projectionCallout(p),
          const SizedBox(height: 12),
          // R4 mockup row: Crop pill + Subscription Deadline tile.
          // Sits directly under the projection callout per the v2 HTML
          // (`page-explore-detail` → "Crop + subscription deadline").
          _cropAndDeadlineRow(p, mock),
          const SizedBox(height: 16),
          // View Area + Photos action tiles removed from Explore Detail
          // per UX call — those previews are owner-side only. Marketplace
          // listings just show the mini-map below + consultation CTA.
          //
          // Growing Technology section was also removed (covered in the
          // consultation call).
          _miniMap(p, mock),
          const SizedBox(height: 16),
          _photoStrip(mock),
          const SizedBox(height: 20),
          _secondaryCta(p),
        ],
      ),
    );
  }

  // ── Hero banner with project image + tier badge top-right. ────────
  Widget _heroBanner(MarketplaceProject p, _ExploreDetailMock mock) {
    final hero = p.marketplaceImage?.isNotEmpty == true
        ? p.marketplaceImage!
        : mock.heroUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hero.isNotEmpty)
              CachedNetworkImage(
                imageUrl: hero,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: ArlColors.sand),
                errorWidget: (_, __, ___) => Container(color: ArlColors.sand),
              )
            else
              Container(color: ArlColors.sand),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.transparent,
                    Colors.black.withOpacity(0.65),
                  ],
                  stops: const [0.0, 0.35, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            if (p.tier.isNotEmpty)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ArlColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    p.tier.toUpperCase(),
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 10,
              child: _statusPill(p),
            ),
            Positioned(
              bottom: 12,
              left: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                  if (p.location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              p.location,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status pill (small, centred-top on the banner). ───────────────
  Widget _statusPill(MarketplaceProject p) {
    String label;
    Color bg;
    Color fg;
    if (p.totalUnits > 0 && p.unitsAvailable == 0) {
      label = 'SOLD OUT';
      bg = ArlColors.accent;
      fg = Colors.white;
    } else if (p.isComingSoon) {
      label = 'COMING SOON';
      bg = ArlColors.primary;
      fg = Colors.white;
    } else if (p.isClosed) {
      label = 'CLOSED';
      bg = ArlColors.earth;
      fg = Colors.white;
    } else {
      final filledPct = p.totalUnits == 0
          ? 0
          : (p.totalUnits - p.unitsAvailable) / p.totalUnits;
      if (filledPct >= 0.7 && filledPct < 1.0) {
        label = 'FILLING FAST';
        bg = ArlColors.gold;
        fg = ArlColors.charcoal;
      } else {
        label = 'OPEN FOR RESERVATION';
        bg = ArlColors.accent;
        fg = Colors.white;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ── Marketplace stats grid.
  //
  // 2026-05-21 redesign: the old "UNITS AVAILABLE" tile (with an inline
  // fill bar) splits into two — "TOTAL UNITS" and "AREA" — and a new
  // remaining-units progress card sits below them so investors can see
  // the sold-vs-available split at a glance.
  Widget _marketplaceStats(MarketplaceProject p) {
    final priceFmt = NumberFormat('#,##,##0.##', 'en_IN');
    final priceText = p.pricePerUnit > 0
        ? '₹${priceFmt.format(p.pricePerUnit / 100000)} L'
        : '—';
    final returnText = p.expectedAnnualReturnPct > 0
        ? '${p.expectedAnnualReturnPct.toStringAsFixed(0)}%'
        : '—';
    final totalText = p.totalUnits > 0 ? '${p.totalUnits}' : '—';
    final acres = p.acreageAcres;
    final acresText = (acres != null && acres > 0)
        ? (acres == acres.truncate()
            ? acres.toStringAsFixed(0)
            : acres.toStringAsFixed(1))
        : '—';
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _statCard(
                label: 'TOTAL UNITS',
                value: totalText,
                subValue: 'across this LLP',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                label: 'AREA',
                value: acresText == '—' ? '—' : '$acresText ac',
                subValue: 'farm land',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _statCard(
                label: 'PRICE PER UNIT',
                value: priceText,
                subValue: '2 acres / unit',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                label: 'EXPECTED RETURN',
                value: returnText,
                subValue: 'per annum',
                valueColor: ArlColors.accent,
                bg: ArlColors.accent.withOpacity(0.08),
                borderColor: ArlColors.accent.withOpacity(0.30),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _remainingUnitsCard(p),
      ],
    );
  }

  // Subscription-progress card — "Remaining: X of Y" with a horizontal
  // bar whose filled portion = sold units (accent green) and empty
  // portion = available units (sand). Sold-out and coming-soon listings
  // get their own status pill instead.
  Widget _remainingUnitsCard(MarketplaceProject p) {
    final total = p.totalUnits;
    final available = p.unitsAvailable;
    final sold = (total - available).clamp(0, total);
    final denom = total == 0 ? 1 : total;
    final fraction = (sold / denom).clamp(0.0, 1.0);

    String headline;
    Color barColor;
    if (total > 0 && available == 0) {
      headline = '$total / $total · Fully subscribed';
      barColor = ArlColors.accent;
    } else if (p.isComingSoon) {
      headline = 'Reservations open soon';
      barColor = ArlColors.muted;
    } else {
      headline = '$available of $total units remaining';
      barColor = ArlColors.accent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SUBSCRIPTION PROGRESS',
                style: TextStyle(
                  color: ArlColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${(fraction * 100).round()}% sold',
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 8,
              color: ArlColors.sand,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: barColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    String? subValue,
    Widget? trailing,
    Color? valueColor,
    Color? bg,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor ?? ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? ArlColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 4),
            Text(
              subValue,
              style: const TextStyle(color: ArlColors.muted, fontSize: 10),
            ),
          ],
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ── Single-line projection callout (no chart, per spec). ──────────
  Widget _projectionCallout(MarketplaceProject p) {
    final pct = p.expectedAnnualReturnPct > 0
        ? '${p.expectedAnnualReturnPct.toStringAsFixed(0)}%'
        : '—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArlColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArlColors.primary.withOpacity(0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: ArlColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Expected annual return: $pct',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text:
                        ' — based on 5-year projection. Detailed financials shared post-allocation.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Crop pill + Subscription Deadline tile.
  //
  // 2-col row matching the HTML `page-explore-detail` "Crop + subscription
  // deadline" block (white crop card on the left, gold-tinted deadline on
  // the right). Crop copy comes from `_ExploreDetailMock.crop` (already
  // includes the emoji); deadline prefers `project.subscriptionDeadline`
  // and falls back to a mock-friendly default so the tile never collapses.
  Widget _cropAndDeadlineRow(MarketplaceProject p, _ExploreDetailMock mock) {
    final cropLabel = mock.crop.isNotEmpty ? mock.crop : '🌱 Mixed crops';
    final deadlineText = _deadlineLabel(p);
    // IntrinsicHeight gives the Row a bounded vertical extent so
    // `CrossAxisAlignment.stretch` doesn't propagate an unbounded
    // height up through the SingleChildScrollView (which caused
    // infinite-scroll behaviour on the Explore detail page).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _miniLabelCard(
              label: 'CROP',
              value: cropLabel,
              bg: Colors.white,
              border: ArlColors.sand,
              valueColor: ArlColors.charcoal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _miniLabelCard(
              label: 'SUBSCRIPTION DEADLINE',
              value: deadlineText,
              bg: ArlColors.gold.withOpacity(0.10),
              border: ArlColors.gold.withOpacity(0.30),
              valueColor: ArlColors.charcoal,
              leadingIcon: Icons.event_outlined,
            ),
          ),
        ],
      ),
    );
  }

  String _deadlineLabel(MarketplaceProject p) {
    final d = p.subscriptionDeadline;
    if (d == null) {
      // Mock-friendly fallback so the tile renders something meaningful
      // even before admins seed `subscription_deadline` in Supabase.
      return 'Dec 31, 2026';
    }
    // Use the default (en_US) locale — preloaded by intl — instead of
    // 'en_IN'. The previous 'en_IN' locale threw `LocaleDataException`
    // because `initializeDateFormatting('en_IN')` is never called in
    // main.dart, which crashed the entire detail screen during build
    // (rendering as a blank gray screen and making it look like tile
    // taps on the Explore page were broken). The format pattern
    // 'd MMM yyyy' produces identical output in either locale (English
    // month abbreviations, day-first order), so dropping the locale
    // argument has no visible effect on the rendered label.
    return DateFormat('d MMM yyyy').format(d);
  }

  // Small label/value card used by the Crop + Deadline row. Kept private
  // because both tiles share the exact same layout — only the colors
  // differ.
  Widget _miniLabelCard({
    required String label,
    required String value,
    required Color bg,
    required Color border,
    required Color valueColor,
    IconData? leadingIcon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 14, color: ArlColors.gold),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ── Mini map — placeholder gradient + circle overlay. Tap anywhere on
  // the map opens Google Maps for the project's approximate location
  // (search query = nearby-town when known, falls back to the project
  // location string). Exact coords never leave the app.
  Widget _miniMap(MarketplaceProject p, _ExploreDetailMock mock) {
    final query = mock.nearTown.isNotEmpty
        ? mock.nearTown.replaceAll('Within 5 km of ', '').trim()
        : p.location;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMap(query),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              colors: [
                ArlColors.sand,
                ArlColors.primary.withOpacity(0.30),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: ArlColors.sand),
          ),
          child: Stack(
            children: [
              // Approximate-area circle overlay — privacy-preserving stand-in
              // until we wire real tiles.
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ArlColors.accent.withOpacity(0.25),
                    border: Border.all(
                      color: ArlColors.accent.withOpacity(0.55),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // "Open in Maps" hint pill top-right.
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new,
                          size: 11, color: ArlColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Open in Maps',
                        style: TextStyle(
                          color: ArlColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 10,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        mock.nearTown.isNotEmpty
                            ? mock.nearTown
                            : 'Approximate location',
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (p.location.isNotEmpty)
                      Flexible(
                        child: Text(
                          p.location,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: ArlColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens Google Maps for the approximate location. Uses the URL-launcher
  /// search endpoint so we don't ship lat/lng — Google handles the
  /// geocoding from the town/region name.
  Future<void> _openMap(String query) async {
    if (query.trim().isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(query)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps')),
      );
    }
  }

  // ── Photo strip (horizontally scrollable thumbnails). ─────────────
  Widget _photoStrip(_ExploreDetailMock mock) {
    final photos = mock.photoStrip;
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent photos',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 110,
                  height: 84,
                  child: CachedNetworkImage(
                    imageUrl: photos[i],
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: ArlColors.sand),
                    errorWidget: (_, __, ___) =>
                        Container(color: ArlColors.sand),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _secondaryCta(MarketplaceProject p) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _openShare(p),
        icon: const Icon(Icons.share, size: 16),
        label: const Text(
          'Share Project',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: ArlColors.primary,
          side: const BorderSide(color: ArlColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  // ── Handlers ──────────────────────────────────────────────────────

  void _openShare(MarketplaceProject p) {
    final mock = _ExploreDetailMock.forProject(p);
    // Pull the real investor's display name from the portfolio provider
    // so the share card + caption show whoever is signed in, not the
    // hardcoded "Sahil Kumar" placeholder.
    final portfolio = ref.read(portfolioSummaryProvider).valueOrNull;
    final sharerName = (portfolio?.investorName.trim().isNotEmpty ?? false)
        ? portfolio!.investorName
        : 'A Growize investor';
    ShareProjectModal.show(
      context,
      project: p,
      heroImageUrl: mock.heroUrl,
      growingTech: mock.tech,
      yieldLabel: mock.yieldValue,
      cropLabel: mock.crop,
      sharerName: sharerName,
    );
  }
}

/// Lightweight placeholder used while data is loading; the `id == ''`
/// sentinel triggers the "not found" branch above.
const _placeholder = MarketplaceProject(
  id: '',
  name: '',
  tagline: '',
  location: '',
  tier: '',
  totalUnits: 0,
  unitsAvailable: 0,
  pricePerUnit: 0,
  expectedAnnualReturnPct: 0,
  llpStatus: '',
);

/// Per-project mock data for fields not stored on `MarketplaceProject`.
///
/// Sourced directly from `EXPLORE_DETAIL_DATA` and `LOCATION_DATA` in
/// the v2 mockup. Keyed by project name (case-insensitive substring)
/// so we don't need to know the Supabase UUIDs ahead of time. Falls
/// back to neutral defaults for listings not in the table.
class _ExploreDetailMock {
  final String heroUrl;
  final String tech;
  final String waterSaved;
  final String yieldValue;
  final String cycles;
  final String lockIn;
  final String crop;
  final String nearTown;
  final List<String> photoStrip;

  const _ExploreDetailMock({
    required this.heroUrl,
    required this.tech,
    required this.waterSaved,
    required this.yieldValue,
    required this.cycles,
    required this.lockIn,
    required this.crop,
    required this.nearTown,
    required this.photoStrip,
  });

  factory _ExploreDetailMock.forProject(MarketplaceProject p) {
    final key = _matchKey(p.name);
    return _byKey[key] ?? _fallback;
  }

  static String _matchKey(String projectName) {
    final n = projectName.toLowerCase();
    if (n.contains('eka')) return 'eka';
    if (n.contains('sunrise ridge')) return 'sr';
    if (n.contains('valley crown')) return 'vc';
    if (n.contains('mystic')) return 'mc';
    if (n.contains('horizon fields')) return 'hf';
    if (n.contains('golden fields')) return 'gf';
    return '';
  }

  static const _fallback = _ExploreDetailMock(
    heroUrl: '',
    tech: 'Aeroponic',
    waterSaved: '95%',
    yieldValue: '30 kg/m²',
    cycles: '7 / yr',
    lockIn: '24 months',
    crop: '',
    nearTown: '',
    photoStrip: <String>[],
  );

  static const _byKey = <String, _ExploreDetailMock>{
    'eka': _ExploreDetailMock(
      heroUrl:
          'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?w=900&q=80&auto=format&fit=crop',
      tech: 'Aeroponic',
      waterSaved: '95%',
      yieldValue: '32 kg/m²',
      cycles: '8 / yr',
      lockIn: '18 months',
      crop: '🍅 Tomatoes & Cucumbers',
      nearTown: 'Within 3 km of Manchar',
      photoStrip: <String>[
        'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?w=400&q=70&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1592921870789-04563d55041c?w=400&q=70&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400&q=70&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=400&q=70&auto=format&fit=crop',
      ],
    ),
    'sr': _ExploreDetailMock(
      heroUrl:
          'https://images.unsplash.com/photo-1464226184884-fa280b87c399?w=900&q=80&auto=format&fit=crop',
      tech: 'Hydroponic',
      waterSaved: '88%',
      yieldValue: '25 kg/m²',
      cycles: '6 / yr',
      lockIn: '24 months',
      crop: '🍓 Strawberries & Herbs',
      nearTown: 'Within 3 km of Wai',
      photoStrip: <String>[
        'https://images.unsplash.com/photo-1464226184884-fa280b87c399?w=400&q=70&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1543158181-e6f9f6712055?w=400&q=70&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400&q=70&auto=format&fit=crop',
      ],
    ),
    'vc': _ExploreDetailMock(
      heroUrl:
          'https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?w=900&q=80&auto=format&fit=crop',
      tech: 'Vertical Aeroponic',
      waterSaved: '96%',
      yieldValue: '38 kg/m²',
      cycles: '9 / yr',
      lockIn: '24 months',
      crop: 'Coconut & Arecanut',
      nearTown: 'Within 3 km of Pen',
      photoStrip: <String>[
        'https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?w=400&q=70&auto=format&fit=crop',
      ],
    ),
  };
}
