import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';

/// B.T6: Demo fallthrough fix.
/// If authenticated (currentInvestorProvider has value), return real data even if empty.
/// Only show demo data when unauthenticated.
final documentsProvider = FutureProvider<List<InvestorDocument>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(documentsRepositoryProvider);

  Future<List<InvestorDocument>> fetchReal() async {
    try {
      return await trackedFetch(ref, () => repo.myDocuments());
    } catch (_) {
      return const <InvestorDocument>[];
    }
  }

  if (SessionManager.isLoggedIn) {
    return fetchReal();
  }

  try {
    final investor = await ref.watch(currentInvestorProvider.future);
    if (investor != null) {
      return fetchReal();
    }
  } catch (_) {}
  return demoDocuments();
});
