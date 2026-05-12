import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/home/models/portfolio_summary.dart';

/// Portfolio summary shown on the dashboard.
///
/// Rule: once an investor row exists for the signed-in user we ALWAYS show
/// real data — even if the numbers are zero (Zoho hasn't synced yet, or
/// they're a fresh investor). The tutorial overlay handles empty-state
/// hand-holding. We only fall back to demo data for the unauthenticated
/// design-preview flow (e.g. SUPABASE_URL not set).
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>((ref) async {
  // Rebuild when auth state flips so a successful sign-in immediately
  // replaces the unauthenticated demo summary with real numbers.
  ref.watch(authStateProvider);

  final financials = ref.watch(financialsRepositoryProvider);

  Future<PortfolioSummary> fetchReal(String name) async {
    try {
      final real = await trackedFetch(
          ref, () => financials.portfolioSummary(investorName: name));
      return real ?? PortfolioSummary.empty(investorName: name);
    } catch (_) {
      // Timeout / unexpected error → render zero-state with the real
      // name so the UI never falls back to skeleton.
      return PortfolioSummary.empty(investorName: name);
    }
  }

  // Signed in: never show demo data — even if currentInvestor is still
  // resolving or returned null. Show a zero-state with a generic name
  // until the real row lands.
  if (SessionManager.isLoggedIn) {
    Map<String, dynamic>? investor;
    try {
      investor = await ref.watch(currentInvestorProvider.future);
    } catch (_) {
      investor = null;
    }
    // Fallback chain: investors.name → user_metadata.name → email-prefix
    // → 'Investor'. Avoids the placeholder "Investor" header when the
    // investor row is still loading or missing.
    final user = ArlSupabase.client?.auth.currentUser;
    final metaName = (user?.userMetadata?['name'] as String?)?.trim();
    final emailLocal = user?.email?.split('@').first;
    final name = (investor?['name'] as String?)?.trim().isNotEmpty == true
        ? (investor!['name'] as String).trim()
        : (metaName != null && metaName.isNotEmpty)
            ? metaName
            : (emailLocal != null && emailLocal.isNotEmpty)
                ? emailLocal
                : 'Investor';
    return fetchReal(name);
  }

  // Unauthenticated design-preview flow → demo browsing.
  return demoPortfolioSummary();
});
