import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/repositories/activity_repository.dart';
import 'package:arl_app/core/repositories/app_config_repository.dart';
import 'package:arl_app/core/repositories/documents_repository.dart';
import 'package:arl_app/core/repositories/financials_repository.dart';
import 'package:arl_app/core/repositories/gallery_repository.dart';
import 'package:arl_app/core/repositories/investor_repository.dart';
import 'package:arl_app/core/repositories/login_events_repository.dart';
import 'package:arl_app/core/repositories/projects_repository.dart';
import 'package:arl_app/core/repositories/support_repository.dart';
import 'package:arl_app/core/repositories/user_settings_repository.dart';
import 'package:arl_app/features/auth/auth_provider.dart';

/// Single source of truth for repository instances. Everything else
/// reads via these — keeps tests easy (override the provider).
final investorRepositoryProvider =
    Provider<InvestorRepository>((_) => InvestorRepository());
final projectsRepositoryProvider =
    Provider<ProjectsRepository>((_) => ProjectsRepository());
final financialsRepositoryProvider =
    Provider<FinancialsRepository>((_) => FinancialsRepository());
final galleryRepositoryProvider =
    Provider<GalleryRepository>((_) => GalleryRepository());
final documentsRepositoryProvider =
    Provider<DocumentsRepository>((_) => DocumentsRepository());
final activityRepositoryProvider =
    Provider<ActivityRepository>((_) => ActivityRepository());
final supportRepositoryProvider =
    Provider<SupportRepository>((_) => SupportRepository());
final appConfigRepositoryProvider =
    Provider<AppConfigRepository>((_) => AppConfigRepository());
final userSettingsRepositoryProvider =
    Provider<UserSettingsRepository>((_) => UserSettingsRepository());
final loginEventsRepositoryProvider =
    Provider<LoginEventsRepository>((_) => LoginEventsRepository());

/// Current user's settings row (toggles + PIN metadata). Rebuilds on auth
/// change so signing-in/out re-fetches. Resolves null when no row exists yet.
final userSettingsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(userSettingsRepositoryProvider);
  try {
    return await repo.mySettings();
  } catch (_) {
    return null;
  }
});

/// Most recent login events for the current user — backs the
/// SecurityScreen login-history list. Rebuilds on auth state changes.
final myLoginEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(loginEventsRepositoryProvider);
  try {
    return await repo.myRecentLogins();
  } catch (_) {
    return const [];
  }
});

/// Cached current investor row (id, name, kyc_status, etc.).
/// Rebuilt when auth state changes — watches authStateProvider so sign-in
/// and sign-out invalidate the cache and re-fetch.
///
/// Always resolves: timeouts and unexpected errors fall through to
/// `null` (treated as "no signed-in investor") rather than putting the
/// provider into AsyncError, which would freeze the UI in skeleton.
final currentInvestorProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(investorRepositoryProvider);
  try {
    return await trackedFetch(ref, () => repo.currentInvestor());
  } catch (_) {
    return null;
  }
});
