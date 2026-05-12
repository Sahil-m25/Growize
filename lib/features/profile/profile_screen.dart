import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/features/home/home_provider.dart';
import 'package:arl_app/features/onboarding/tutorial_provider.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investor = ref.watch(currentInvestorProvider).valueOrNull;
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final portfolio = ref.watch(portfolioSummaryProvider).valueOrNull;
    final investorName = (investor?['name'] as String?) ??
        (projects.isNotEmpty ? 'Investor' : 'Sahil Kumar');
    final investorArl = (investor?['arl_id'] as String?) ?? 'ARL-DEMO';
    final kycStatus = (investor?['kyc_status'] as String?) ?? 'verified';
    final kycVerified = kycStatus == 'verified';
    final initials = _initials(investorName);
    final projectCount = projects.length;
    final investedLabel = portfolio == null
        ? null
        : Money.inr(portfolio.totalInvested, inline: true);
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ArlColors.primary, ArlColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                investorName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                investorArl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: kycVerified
                                          ? ArlColors.gold
                                          : ArlColors.earth,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    kycVerified
                                        ? 'KYC Verified'
                                        : 'KYC: ${kycStatus.replaceAll('_', ' ')}',
                                    style: const TextStyle(
                                      color: ArlColors.goldLight,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Stats strip: project count + total invested.
                    // Source: portfolio_summary view via portfolioSummaryProvider.
                    Text(
                      investedLabel == null
                          ? '$projectCount ${projectCount == 1 ? "Project" : "Projects"}'
                          : '$projectCount ${projectCount == 1 ? "Project" : "Projects"} · $investedLabel invested',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Active Projects card (HTML parity — single line · separated)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: ArlColors.sand, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Active Projects',
                        style: TextStyle(
                          color: ArlColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        projects.isEmpty
                            ? 'No active projects yet'
                            : projects.map((p) => p.name).join(' · '),
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Account Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Account'),
                    _menuTile(
                      context,
                      icon: Icons.person_outline,
                      title: 'KYC Details',
                      route: RouteNames.kyc,
                      badge: 'Verified',
                    ),
                    _menuTile(
                      context,
                      icon: Icons.account_balance_outlined,
                      title: 'Bank Details',
                      route: RouteNames.bankDetails,
                    ),
                    _menuTile(
                      context,
                      icon: Icons.description_outlined,
                      title: 'Documents',
                      route: RouteNames.documents,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Support Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Support'),
                    _menuTile(
                      context,
                      icon: Icons.help_outline,
                      title: 'Assistance',
                      route: RouteNames.support,
                    ),
                    _menuTile(
                      context,
                      icon: Icons.exit_to_app_outlined,
                      title: 'Project Exit',
                      route: RouteNames.exit,
                    ),
                    _menuTile(
                      context,
                      icon: Icons.lock_outline,
                      title: 'Security',
                      route: RouteNames.security,
                    ),
                    _replayTutorialTile(context, ref),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Sign Out — text-only destructive action on white card,
              // matching HTML pattern (NOT a filled Material destructive button).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: ArlColors.sand, width: 1),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      await SessionManager.signOut();
                      if (context.mounted) context.go(RouteNames.auth);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: ArlColors.earth,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(
                        color: ArlColors.earth,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Bound to a ref so it can mutate the tutorial state. Same visual
  /// shape as [_menuTile] but routes via [replayTutorial] instead of
  /// pushing a screen.
  Widget _replayTutorialTile(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        await replayTutorial(ref);
        if (context.mounted) context.go(RouteNames.home);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ArlColors.sand, width: 1),
        ),
        child: const Row(
          children: [
            Icon(Icons.play_circle_outline, color: ArlColors.primary, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Replay Tour',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: ArlColors.primary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    String? badge,
  }) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ArlColors.sand,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: ArlColors.primary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: ArlColors.primary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
