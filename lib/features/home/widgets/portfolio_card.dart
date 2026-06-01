import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';

class PortfolioCard extends ConsumerStatefulWidget {
  final PortfolioSummary portfolio;

  const PortfolioCard({
    required this.portfolio,
    super.key,
  });

  @override
  ConsumerState<PortfolioCard> createState() => _PortfolioCardState();
}

class _PortfolioCardState extends ConsumerState<PortfolioCard> {
  bool _showValues = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render every 30s so "Updated Xm ago" stays accurate without
    // forcing a refetch.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalValue = widget.portfolio.totalInvested;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            // Main card
            Container(
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: label + inline eye (LEFT) — Updated badge (RIGHT)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'TOTAL PORTFOLIO VALUE',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _showValues = !_showValues),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  _showValues
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _showValues ? Money.inr(totalValue) : '••••••',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SyncBadge(
                    isLive: ref.watch(isLiveProvider),
                    syncedAt: ref.watch(lastSyncAtProvider),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Stats grid (2 columns)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INVESTED',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _showValues
                                ? Money.inr(widget.portfolio.totalInvested,
                                    inline: true)
                                : '••••••',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RETURNS',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _showValues
                                ? '+${Money.inr(widget.portfolio.totalReceived, inline: true)}'
                                : '••••••',
                            style: const TextStyle(
                              color: ArlColors.goldLight,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ROI row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.portfolio.roiPercent}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Annual ROI',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: ArlColors.gold.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Outperforming',
                            style: TextStyle(
                              color: ArlColors.goldLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'vs 12% Nifty',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Decorative circle top-right
        Positioned(
          top: -30,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ArlColors.gold.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sync indicator pill. Matches HTML `sync-badge`:
///   * **Live state** (`< 60s` since last successful sync OR a fetch is
///     in-flight) → pulsing green dot + uppercase "LIVE" label.
///   * **Aged state** (>= 60s old, or unknown) → small clock glyph +
///     `Updated Xm ago`.
///
/// The 60s window is what makes the pill feel honest: it stays "Live"
/// long enough that a user who refreshes still sees the affirmation,
/// but it doesn't lie if the screen has been sitting on-device for a
/// while.
class _SyncBadge extends StatefulWidget {
  final bool isLive;
  final DateTime? syncedAt;

  const _SyncBadge({required this.isLive, required this.syncedAt});

  @override
  State<_SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<_SyncBadge>
    with SingleTickerProviderStateMixin {
  /// Threshold: any sync that completed inside this window keeps the
  /// "Live" affordance — matches the HTML mockup's behaviour where the
  /// pulse stays on for ~1 min after a refresh.
  static const Duration _liveWindow = Duration(seconds: 60);

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _showLive {
    if (widget.isLive) return true;
    final t = widget.syncedAt;
    if (t == null) return false;
    return DateTime.now().difference(t) < _liveWindow;
  }

  @override
  Widget build(BuildContext context) {
    final live = _showLive;
    final label = live
        ? 'Live'
        : formatSyncLabel(syncedAt: widget.syncedAt, isLive: false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  // Spec asks for `#00C853` — we use the brand accent
                  // (which is the green that already appears on the
                  // Operational pill and progress bars) so the dot reads
                  // as "the app's healthy-green", not an arbitrary
                  // material green imported just for this badge.
                  color: ArlColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            Icon(
              Icons.schedule,
              size: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          const SizedBox(width: 6),
          Text(
            // Uppercase Live label per HTML; "Updated…" labels stay
            // mixed-case because they're a sentence, not a status pill.
            live ? label.toUpperCase() : label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: live ? 0.8 : 0,
            ),
          ),
        ],
      ),
    );
  }
}
