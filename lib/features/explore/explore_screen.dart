import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Explore — discover new investment opportunities.
///
/// Source of truth: `public.projects` rows where
/// `is_listed_in_marketplace = true`. Admins toggle this in Supabase
/// Studio — no app rebuild required.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  MarketplaceProject? _selected;
  int _selectedUnits = 1;
  double _customUnits = 1;
  bool _useCustomUnits = false;
  String _statusFilter = 'all'; // all | open | not_started
  final Set<String> _submittingProjectIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    final marketplaceAsync = ref.watch(marketplaceProjectsProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ArlColors.sand,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'New Projects',
                            style: TextStyle(
                              color: ArlColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Browse upcoming offerings — request a consultation and our team will reach out.',
                  style: TextStyle(color: ArlColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),

                // Filter pills
                Row(
                  children: [
                    _filterPill('All', 'all'),
                    const SizedBox(width: 8),
                    _filterPill('Open for Reservation', 'open'),
                    const SizedBox(width: 8),
                    _filterPill('Coming soon', 'not_started'),
                  ],
                ),
                const SizedBox(height: 16),

                // Listings.
                //
                // UX rule: never show a blank screen or raw error string.
                // Order of precedence:
                //   1. Have data (fresh or cached) → render it, even while
                //      a refetch is in flight (skipLoadingOnReload). The
                //      _SyncBadge on the home tab signals "Live" during
                //      that window.
                //   2. No data yet + still loading → skeleton.
                //   3. No data yet + error → skeleton (repo already
                //      tried cache; this is the last-resort safety net).
                _resolveListings(marketplaceAsync, formatter),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Resolves the listings render branch. Pulls cached data through
  /// reloads + errors so the UI never blanks once we've fetched at least
  /// once. Falls back to a skeleton only on a cold start with no cache.
  Widget _resolveListings(
    AsyncValue<List<MarketplaceProject>> async,
    NumberFormat formatter,
  ) {
    final cached = async.valueOrNull;
    if (cached != null) {
      final filtered = _applyFilter(cached, _statusFilter);
      if (filtered.isEmpty) return _emptyState();
      if (_selected == null || !filtered.any((p) => p.id == _selected!.id)) {
        _selected = filtered.first;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelector(filtered),
          const SizedBox(height: 16),
          _buildDetailsCard(_selected!, formatter),
          const SizedBox(height: 20),
          _buildProjection(_selected!, formatter),
          const SizedBox(height: 12),
          const Text(
            'Disclaimer: Past returns do not guarantee future results. Investments carry risk.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ArlColors.muted, fontSize: 9),
          ),
          const SizedBox(height: 20),
        ],
      );
    }
    // No data yet — loading or error. Show skeleton either way.
    return _listingsSkeleton();
  }

  List<MarketplaceProject> _applyFilter(
    List<MarketplaceProject> listings,
    String filter,
  ) {
    switch (filter) {
      case 'open':
        // "Open for reservation" = subscription window active and at least
        // one unit free. Includes brand-new listings (units_available ==
        // total_units) — those ARE the most open of all.
        return listings
            .where((p) => !p.isClosed && p.unitsAvailable > 0)
            .toList();
      case 'not_started':
        return listings.where((p) => p.isNotYetStarted).toList();
      case 'all':
      default:
        return listings;
    }
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

  /// Skeleton placeholder shown while marketplace data is loading or
  /// when we have no cache yet. Same vertical rhythm as the real card so
  /// nothing jumps when data arrives.
  Widget _listingsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
              child: _skelBox(width: 110, height: 36, radius: 18),
            );
          }),
        ),
        const SizedBox(height: 16),
        _skelBox(height: 200, radius: 15),
        const SizedBox(height: 20),
        _skelBox(height: 120, radius: 15),
      ],
    );
  }

  Widget _skelBox({double? width, required double height, double radius = 12}) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: ArlColors.sand.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
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
    );
  }

  Widget _buildSelector(List<MarketplaceProject> listings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArlColors.sand),
      ),
      child: DropdownButton<MarketplaceProject>(
        value: _selected,
        onChanged: (project) {
          if (project != null) {
            setState(() {
              _selected = project;
              _selectedUnits = 1;
              _customUnits = 1;
            });
          }
        },
        underline: Container(),
        isExpanded: true,
        items: listings
            .map(
              (project) => DropdownMenuItem(
                value: project,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _statusBadge(project),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _statusBadge(MarketplaceProject p) {
    String label;
    Color bg;
    Color fg;
    if (p.isClosed) {
      label = 'Closed';
      bg = ArlColors.earth.withValues(alpha: 0.15);
      fg = ArlColors.earth;
    } else if (p.isNotYetStarted) {
      label = 'Coming soon';
      bg = ArlColors.gold.withValues(alpha: 0.2);
      fg = ArlColors.primary;
    } else {
      label = 'Open';
      bg = ArlColors.accent.withValues(alpha: 0.15);
      fg = ArlColors.accent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDetailsCard(MarketplaceProject p, NumberFormat formatter) {
    final unitCount = _useCustomUnits ? _customUnits.toInt() : _selectedUnits;
    final totalInvestment = unitCount * p.pricePerUnit;
    final annualReturn = totalInvestment * (p.expectedAnnualReturnPct / 100);
    final deadlineFmt = p.subscriptionDeadline != null
        ? DateFormat('d MMM y').format(p.subscriptionDeadline!)
        : '—';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ArlColors.primary, ArlColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.tagline.isNotEmpty)
            Text(
              p.tagline,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 12),

          // Project details
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _detailRow('Location', p.location.isEmpty ? '—' : p.location),
                if (p.acreageAcres != null)
                  _detailRow('Farm Size', '${p.acreageAcres} acres'),
                if (p.cropType != null && p.cropType!.isNotEmpty)
                  _detailRow('Crop', p.cropType!),
                _detailRow('Tier', p.tier.isEmpty ? '—' : p.tier),
                _detailRow('Total Units', '${p.totalUnits}'),
                _detailRow('Available Units', '${p.unitsAvailable}'),
                _detailRow('Subscription Deadline', deadlineFmt),
                _detailRow(
                  'Price / Unit',
                  '₹${formatter.format(p.pricePerUnit / 100000)}L',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Units selector
          Text(
            'Units to subscribe',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$unitCount Unit${unitCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Slider(
                  value: _useCustomUnits
                      ? _customUnits
                      : _selectedUnits.toDouble(),
                  onChanged: p.unitsAvailable > 0
                      ? (value) {
                          setState(() {
                            if (_useCustomUnits) {
                              _customUnits = value;
                            } else {
                              _selectedUnits = value.toInt();
                            }
                          });
                        }
                      : null,
                  min: 1,
                  max: p.unitsAvailable > 0
                      ? p.unitsAvailable.toDouble().clamp(1, 50)
                      : 10,
                  activeColor: ArlColors.gold,
                  inactiveColor: Colors.white.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Checkbox(
                value: _useCustomUnits,
                onChanged: (value) {
                  setState(() {
                    _useCustomUnits = value ?? false;
                  });
                },
                fillColor: WidgetStateProperty.all(
                  Colors.white.withValues(alpha: 0.3),
                ),
              ),
              Text(
                'Enter custom units',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (_useCustomUnits)
            TextField(
              decoration: InputDecoration(
                hintText: 'Units (1-${p.unitsAvailable})',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final v = double.tryParse(value);
                if (v != null) {
                  setState(
                    () => _customUnits = v.clamp(
                      1.0,
                      p.unitsAvailable.toDouble().clamp(1.0, 50.0),
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 16),

          // Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Investment Summary',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  'Total Investment',
                  '₹${formatter.format(totalInvestment / 100000)}L',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  'Est. Annual Return',
                  '₹${formatter.format(annualReturn / 100000)}L',
                  highlight: true,
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  'Expected Yield',
                  '${p.expectedAnnualReturnPct.toStringAsFixed(0)}% p.a.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (p.unitsAvailable > 0 &&
                      !p.isClosed &&
                      !_submittingProjectIds.contains(p.id))
                  ? () => _onConsultationRequested(p, unitCount)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD264),
                foregroundColor: ArlColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _submittingProjectIds.contains(p.id)
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        color: ArlColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      p.isClosed
                          ? 'Subscription Closed'
                          : p.unitsAvailable == 0
                          ? 'Fully Subscribed'
                          : 'Request Consultation',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjection(MarketplaceProject p, NumberFormat formatter) {
    final unitCount = _useCustomUnits ? _customUnits.toInt() : _selectedUnits;
    final totalInvestment = unitCount * p.pricePerUnit;
    final ratePerYr = p.expectedAnnualReturnPct / 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '5-Year Projection',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'Based on $unitCount unit${unitCount == 1 ? '' : 's'} · ${p.name}',
            style: const TextStyle(color: ArlColors.muted, fontSize: 10),
          ),
          const SizedBox(height: 12),
          ...List.generate(5, (idx) {
            final year = idx + 1;
            // Compound growth: (1 + r)^n
            final multiplier = _pow(1 + ratePerYr, year);
            final pctGain = ((multiplier - 1) * 100).toStringAsFixed(1);
            final amount = totalInvestment * multiplier;
            // Bar width proportional to compound growth (Y5 = full bar).
            final maxMultiplier = _pow(1 + ratePerYr, 5);
            final barFraction = maxMultiplier > 1
                ? (multiplier - 1) / (maxMultiplier - 1)
                : (idx + 1) / 5;
            final barColor = Color.lerp(
              ArlColors.primary,
              ArlColors.gold,
              idx / 4,
            )!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          'Y$year',
                          style: const TextStyle(
                            color: ArlColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: barFraction.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: ArlColors.sand,
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '₹${formatter.format(amount / 100000)}L',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Text(
                      '+$pctGain% cumulative gain',
                      style: TextStyle(
                        color: barColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _onConsultationRequested(MarketplaceProject p, int units) async {
    if (_submittingProjectIds.contains(p.id)) return;
    setState(() => _submittingProjectIds.add(p.id));

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(consultationRequestsRepositoryProvider)
          .createConsultation(projectId: p.id, unitsRequested: units);
      if (!mounted) return;
      final unitLabel = '$units unit${units == 1 ? '' : 's'}';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.created
                ? 'Got it — our team will reach out about $unitLabel of ${p.name}.'
                : 'You already requested a consultation for ${p.name} recently. We\'ll be in touch.',
          ),
          backgroundColor: ArlColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not submit request: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingProjectIds.remove(p.id));
      }
    }
  }

  /// Simple integer power for compound growth — avoids importing dart:math
  /// just for pow(). Only used with small integer exponents (1-5).
  static double _pow(double base, int exp) {
    double result = 1.0;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: highlight ? ArlColors.goldLight : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
