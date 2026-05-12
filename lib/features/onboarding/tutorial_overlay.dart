import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/onboarding/tutorial_provider.dart';

/// Full-screen onboarding carousel that surfaces over the rest of the
/// UI. Uses sample numbers (mock) to illustrate each section before the
/// investor's real Zoho data has synced.
///
/// Mounted at the scaffold level (see main_scaffold.dart). Reads
/// [shouldShowTutorialProvider] to decide visibility.
class TutorialOverlay extends ConsumerStatefulWidget {
  const TutorialOverlay({super.key});

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends ConsumerState<TutorialOverlay> {
  final _controller = PageController();
  int _index = 0;

  static const _steps = <_Step>[
    _Step(
      icon: Icons.dashboard_customize,
      title: 'Welcome to ARL',
      body:
          'Your investor dashboard. We\'ll walk you through the four main areas in under 30 seconds.',
      sampleLabel: 'TOTAL PORTFOLIO',
      sampleValue: '₹1.20 Cr',
      sampleSub: 'Sample • your real numbers will appear here once allocated',
    ),
    _Step(
      icon: Icons.show_chart,
      title: 'Track Every Project',
      body:
          'Each LLP you have units in shows here with progress, contract month, and live status — Operational, Pending, or Awaiting Payment.',
      sampleLabel: 'PINEAPPLE ENTERPRISES',
      sampleValue: 'Month 4 of 60',
      sampleSub: '7% complete • Operational',
    ),
    _Step(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Payouts & Financials',
      body:
          'Every payout from every project lands in your transaction ledger. UTR references, status, and per-FY summaries — all in one place.',
      sampleLabel: 'NEXT PAYOUT',
      sampleValue: '₹1,25,000',
      sampleSub: 'Pineapple Enterprises • 15 May',
    ),
    _Step(
      icon: Icons.explore_outlined,
      title: 'Discover New Projects',
      body:
          'New farming offerings appear in Explore as our team curates them. Subscribe with one tap and we\'ll reach out for the consultation.',
      sampleLabel: 'COMING SOON',
      sampleValue: 'Pineapple Enterprises',
      sampleSub: 'Open for reservation • 19% expected yield',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _steps.length - 1;

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Top row — Skip
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => dismissTutorial(ref),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ArlColors.cream,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 360,
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemCount: _steps.length,
                          itemBuilder: (context, i) => _buildStep(_steps[i]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _steps.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? ArlColors.primary
                                  : ArlColors.sand,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (isLast) {
                              dismissTutorial(ref);
                            } else {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ArlColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isLast ? 'Get Started' : 'Next',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(_Step step) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ArlColors.primary, ArlColors.accent],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(step.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            step.title,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // Sample card to show the shape of real data
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ArlColors.primary, ArlColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.sampleLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  step.sampleValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.sampleSub,
                  style: TextStyle(
                    color: ArlColors.goldLight.withValues(alpha: 0.85),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final String sampleLabel;
  final String sampleValue;
  final String sampleSub;

  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.sampleLabel,
    required this.sampleValue,
    required this.sampleSub,
  });
}
