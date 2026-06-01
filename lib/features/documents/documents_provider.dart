import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/connectivity/sync_state.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';
import 'package:arl_app/features/documents/models/project_document.dart';

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

/// Every project document visible to the current investor across ALL
/// the projects they have non-zero allocations in. RLS does the
/// filtering server-side — see migration 054. Backs the
/// "Project Documents" section on the Documents tab.
///
/// Unauthenticated users (and demo mode) get an empty list rather than
/// mock data — the per-investor `documentsProvider` already covers the
/// demo story and adding mock project docs would just confuse the
/// grouping UI.
final allProjectDocumentsProvider =
    FutureProvider.autoDispose<List<ProjectDocument>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(documentsRepositoryProvider);

  if (!SessionManager.isLoggedIn) {
    try {
      final investor = await ref.watch(currentInvestorProvider.future);
      if (investor == null) return const <ProjectDocument>[];
    } catch (_) {
      return const <ProjectDocument>[];
    }
  }

  try {
    return await trackedFetch(ref, () => repo.myProjectDocuments());
  } catch (_) {
    return const <ProjectDocument>[];
  }
});

/// Per-project variant — used by the project detail screen to render
/// a small horizontally-scrolling row of docs scoped to a single LLP.
///
/// `family` keyed on `projectId` so each project gets its own cache
/// entry; `autoDispose` so the row evaporates when the user leaves the
/// project detail screen (no need to hold onto signed URLs).
final projectDocumentsProvider =
    FutureProvider.autoDispose.family<List<ProjectDocument>, String>(
  (ref, projectId) async {
    ref.watch(authStateProvider);
    final repo = ref.watch(documentsRepositoryProvider);
    if (projectId.isEmpty) return const <ProjectDocument>[];

    try {
      return await trackedFetch(ref, () => repo.projectDocuments(projectId));
    } catch (_) {
      return const <ProjectDocument>[];
    }
  },
);
