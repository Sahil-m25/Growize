import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';

import 'celebration_flag.dart';

/// Full-screen "Your first payout has arrived" overlay.
///
/// Reached via `/celebration?amount=...&project=...&date=...`. The screen
/// is intentionally static — no animations — matching the HTML mockup's
/// `page-celebration` (see Growize_App_Design_v2_proposed.html, line 2047).
class CelebrationScreen extends StatelessWidget {
  /// Amount credited (INR rupees, not paise).
  final double amount;

  /// Project name (e.g. "EKA").
  final String projectName;

  /// Payout date.
  final DateTime date;

  const CelebrationScreen({
    super.key,
    required this.amount,
    required this.projectName,
    required this.date,
  });

  void _viewInFinancials(BuildContext context) {
    // Pop the celebration off the stack, then route to Financials.
    if (context.canPop()) context.pop();
    context.go(RouteNames.financials);
  }

  Future<void> _shareStory(BuildContext context) async {
    // T2 will build the real share modal. Stub dialog for now so the
    // CTA isn't a dead button.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArlColors.cream,
        title: const Text(
          'Share your investment story',
          style: TextStyle(
            color: ArlColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'Share modal opens here (T2 builds it).',
          style: TextStyle(color: ArlColors.charcoal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: ArlColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeLater(BuildContext context) async {
    if (context.canPop()) context.pop();
    await CelebrationFlag.markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM dd, yyyy').format(date);
    final amountLabel = '${Money.inr(amount, inline: true)} credited';

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Confetti illustration. Static — no animation, per spec.
              _ConfettiHeader(onClose: () => _maybeLater(context)),

              // Body copy + CTAs.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your first payout has arrived',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ArlColors.primary,
                        fontSize: 24, // text-2xl
                        fontWeight: FontWeight.w600, // semibold
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      amountLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ArlColors.accent,
                        fontSize: 36, // text-4xl
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'From $projectName · $dateLabel',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ArlColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Primary CTA — gradient pill, matches the HTML.
                    _PrimaryCta(
                      label: 'View in Financials',
                      icon: Icons.trending_up,
                      onPressed: () => _viewInFinancials(context),
                    ),
                    const SizedBox(height: 10),

                    // Secondary CTA — outlined.
                    _SecondaryCta(
                      label: 'Share your investment story',
                      icon: Icons.ios_share,
                      onPressed: () => _shareStory(context),
                    ),
                    const SizedBox(height: 12),

                    // "Maybe later" link.
                    Center(
                      child: TextButton(
                        onPressed: () => _maybeLater(context),
                        style: TextButton.styleFrom(
                          foregroundColor: ArlColors.muted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        child: const Text(
                          'Maybe later',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
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
}

// ─── Confetti header ────────────────────────────────────────────────────
//
// CustomPainter draws rectangular confetti in arl.gold / arl.accent /
// arl.earth; sparkle icons are overlaid as the "Lucide sparkles" stand-in
// using Material's auto_awesome (closest visual match in the default font).

class _ConfettiHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _ConfettiHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ConfettiPainter()),
          ),
          // Lucide-style sparkles overlay. Static positions taken from the
          // HTML mockup (top-left / top-right / bottom-left / bottom-right).
          const Positioned(
            top: 24,
            left: 32,
            child: Icon(
              Icons.auto_awesome,
              size: 22,
              color: ArlColors.gold,
            ),
          ),
          const Positioned(
            top: 48,
            right: 40,
            child: Icon(
              Icons.auto_awesome,
              size: 26,
              color: ArlColors.accent,
            ),
          ),
          const Positioned(
            bottom: 32,
            left: 48,
            child: Icon(
              Icons.auto_awesome,
              size: 18,
              color: ArlColors.earth,
            ),
          ),
          const Positioned(
            bottom: 40,
            right: 24,
            child: Icon(
              Icons.auto_awesome,
              size: 22,
              color: ArlColors.goldLight,
            ),
          ),
          // Close (x) button top-right — matches HTML's
          // `bg-white/60 backdrop-blur-sm rounded-full` pattern.
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: ArlColors.charcoal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  // Pre-computed rectangle placements. Each entry is:
  // [xFrac, yFrac, width, height, rotationDeg, colorIndex]
  // — xFrac/yFrac are relative to the canvas so the layout scales with
  // device width. Static, hand-tuned to feel scattered like the HTML.
  static const List<List<double>> _rects = [
    [0.10, 0.11, 8, 8, 20, 0],
    [0.22, 0.30, 6, 14, -30, 1],
    [0.40, 0.07, 10, 6, 45, 2],
    [0.57, 0.22, 6, 12, 60, 0],
    [0.75, 0.13, 8, 8, -15, 1],
    [0.88, 0.34, 6, 12, 35, 1],
    [0.15, 0.62, 10, 6, -20, 0],
    [0.65, 0.58, 6, 14, 50, 2],
    [0.30, 0.78, 8, 8, 15, 0],
    [0.80, 0.78, 10, 6, -35, 1],
    [0.50, 0.45, 7, 7, 25, 2],
    [0.05, 0.42, 6, 10, -10, 1],
  ];

  static const List<Color> _palette = [
    ArlColors.gold,
    ArlColors.accent,
    ArlColors.earth,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final r in _rects) {
      final cx = r[0] * size.width;
      final cy = r[1] * size.height;
      final w = r[2];
      final h = r[3];
      final rot = r[4] * math.pi / 180.0;
      final colorIdx = r[5].toInt() % _palette.length;
      paint.color = _palette[colorIdx];

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── CTA buttons ────────────────────────────────────────────────────────

class _PrimaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryCta({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ArlColors.primary, ArlColors.accent],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: ArlColors.primary.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _SecondaryCta({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.primary),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: ArlColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: ArlColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
