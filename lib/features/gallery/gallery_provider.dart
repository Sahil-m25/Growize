import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/mock/demo_data.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/gallery/models/gallery_photo.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// B.T6: Demo fallthrough fix.
/// If authenticated (currentInvestorProvider has value), return real data even if empty.
/// Only show demo data when unauthenticated.
final galleryProvider = FutureProvider<List<GalleryPhoto>>((ref) async {
  ref.watch(authStateProvider);
  final selectedId = ref.watch(selectedProjectIdProvider);
  final repo = ref.watch(galleryRepositoryProvider);

  Future<List<GalleryPhoto>> fetchReal() {
    final scope = (selectedId != null && !selectedId.startsWith(demoIdPrefix))
        ? selectedId
        : null;
    return repo.photos(projectId: scope);
  }

  if (SessionManager.isLoggedIn) {
    try {
      return await fetchReal();
    } catch (_) {
      return const <GalleryPhoto>[];
    }
  }

  try {
    final investor = await ref.watch(currentInvestorProvider.future);
    if (investor != null) {
      return await fetchReal();
    }
  } catch (_) {}
  return demoGalleryPhotos(projectId: selectedId);
});
