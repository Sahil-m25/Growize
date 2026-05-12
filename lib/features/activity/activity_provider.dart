import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/activity/models/notification.dart';
import 'package:arl_app/features/auth/auth_provider.dart';

/// B.T6: Demo fallthrough fix.
/// If currentInvestorProvider has a value (authenticated), always return real data,
/// even if empty. Only show demo data when unauthenticated.
final notificationsProvider =
    FutureProvider<List<ArlNotification>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(activityRepositoryProvider);

  Future<List<ArlNotification>> fetchReal() async {
    try {
      return await trackedFetch(ref, () => repo.notifications());
    } catch (_) {
      return const <ArlNotification>[];
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
  return demoNotifications();
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  try {
    final list = await ref.watch(notificationsProvider.future);
    return list.where((n) => !n.isRead).length;
  } catch (_) {
    return 0;
  }
});
