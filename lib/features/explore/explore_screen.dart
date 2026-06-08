import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/explore/widgets/project_tile.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Explore — discover new investment opportunities (marketplace mode).
///
/// Source of truth: `public.projects` rows where
/// `is_listed_in_marketplace = true`. Tapping a tile routes to
/// `/explore/<id>` for the marketplace detail view.
///
/// v2 layout (mirrors `page-explore` in the design HTML): header, filter
/// pills, 2-column tile grid. The legacy selector-chip + inline detail
/// card layout has been retired — detail lives on its own page now.
///
/// DEF-V32-AUTH-04 decision (kept as 4 pills, deliberate spec deviation):
/// The HTML mockup ships three filter pills — All / Open for Reservation
/// / Coming soon. The Flutter app adds a fourth, "Closed", because an
/// investor genuinely wants to look back at past deals (post-allocation
/// audit, returning-investor flows, historical references for the RM
/// call). The extra pill is an intentional improvement over the v2 spec,
/// not a defect — do NOT remove without product-side sign-off.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _statusFilter = 'all'; // all | open | not_started | closed

  // Set to true once marketplace listings are ready to show.
  // Everything is wired up behind this flag — flip it to re-enable.
  static const bool _marketplaceEnabled = false;

  @override
  Widget build(BuildContext context) {
    final marketplaceAsync = ref.watch(marketplaceProjectsProvider);

    final content = Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Explore',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Upcoming offerings — tap any tile for details.',
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _filterRow(),
              const SizedBox(height: 14),
              Expanded(child: _content(marketplaceAsync)),
            ],
          ),
        ),
      ),
    );

    if (_marketplaceEnabled) return content;

    // Marketplace not yet live — show a Coming Soon overlay.
    // The full implementation is active behind the flag so there's
    // nothing to rebuild when we flip it on.
    return Stack(
      children: [
        content,
        Positioned.fill(
          child: Container(
            color: ArlColors.cream,
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: ArlColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: ArlColors.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Coming Soon',
                    style: TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'New investment opportunities will appear here. '
                      'Stay tuned for upcoming offerings from ARL.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ArlColors.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Filter pills row — see DEF-V32-AUTH-04 note above; this row
  // ships with 4 pills (All / Open / Coming soon / Closed) on purpose.
  // The HTML mockup only has 3 — the Closed pill is an intentional
  // addition for investor-side history browsing.
  Widget _filterRow() {
    return SingleChildScrollView(
      key: TourKeys.exploreFilters,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterPill('All', 'all'),
          const SizedBox(width: 8),
          _filterPill('Open for Reservation', 'open'),
          const SizedBox(width: 8),
          _filterPill('Coming soon', 'not_started'),
          const SizedBox(width: 8),
          _filterPill('Closed', 'closed'),
        ],
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final active = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ArlColors.primary : ArlColors.sand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : ArlColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Resolve list state into a grid / skeleton / empty. ────────────
  //
  // Order of precedence (matches the convention used elsewhere in the
  // app):
  //   1. Have data (fresh or cached) → render the grid, even while
  //      a refetch is in flight. The home tab's _SyncBadge signals
  //      "Live" during that window.
  //   2. No data yet + still loading → skeleton.
  //   3. No data yet + error → skeleton (repos already tried cache;
  //      this is the last-resort safety net).
  Widget _content(AsyncValue<List<MarketplaceProject>> async) {
    final cached = async.valueOrNull;
    if (cached != null) {
      final filtered = _applyFilter(cached, _statusFilter);
      if (filtered.isEmpty) return _emptyState();
      return _grid(filtered);
    }
    // No data + error → friendly retry card instead of an endless skeleton.
    if (async.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: ErrorRetryView(
          message: 'We could not load opportunities. '
              "Tap retry once you're back online.",
          onRetry: () => ref.invalidate(marketplaceProjectsProvider),
        ),
      );
    }
    return _skeleton();
  }

  List<MarketplaceProject> _applyFilter(
    List<MarketplaceProject> listings,
    String filter,
  ) {
    switch (filter) {
      case 'open':
        // Open for Reservation: subscription window active AND at least
        // one unit has already been issued (units_available <
        // total_units). Excludes brand-new placeholder listings, which
        // are exclusively surfaced under "Coming Soon" — see the
        // mutually-exclusive getters on MarketplaceProject.
        return listings.where((p) => p.isOpenForReservation).toList();
      case 'not_started':
        // Coming Soon: subscription window active AND no units issued
        // yet (placeholder listing).
        return listings.where((p) => p.isComingSoon).toList();
      case 'closed':
        // Closed: subscription window has passed.
        return listings.where((p) => p.isClosed).toList();
      case 'all':
      default:
        return listings;
    }
  }

  Widget _grid(List<MarketplaceProject> items) {
    return GridView.builder(
      key: TourKeys.exploreGrid,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Cap tile width at ~320 so at wide desktop widths we get more
        // columns instead of one or two giant tiles whose body content
        // ends up below the fold. On a phone (≤640px), this still yields
        // 2 columns matching the mockup.
        maxCrossAxisExtent: 320,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Tiles are taller than they are wide — hero (16:10) + body of
        // name/location/chip/fill/price. ~0.66 keeps the body un-cramped
        // without leaving whitespace below the price.
        childAspectRatio: 0.66,
      ),
      itemBuilder: (_, i) => ProjectTile(project: items[i]),
    );
  }

  // ── Skeleton — 4 placeholder tiles on cold start. ─────────────────
  Widget _skeleton() {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            color: ArlColors.sand.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco_outlined, color: ArlColors.muted, size: 36),
            const SizedBox(height: 8),
            const Text(
              'No new projects right now',
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _statusFilter == 'all'
                  ? 'Check back soon — our team is curating the next round.'
                  : 'No listings match this filter. Try "All".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
