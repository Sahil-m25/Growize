import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/mock/mock_data.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/gallery/gallery_provider.dart';
import 'package:arl_app/features/gallery/models/gallery_photo.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Per-project photos screen pushed from the project detail page.
///
/// Renders a 2-column GridView of rounded photo tiles. Tapping a tile
/// pushes a fullscreen Hero with an [InteractiveViewer] for pinch-zoom.
///
/// Data sources, in order of preference:
///   1. `galleryProvider` — real Supabase-backed photos filtered to this
///      project. Falls back automatically when empty.
///   2. `mockGalleryPhotos` from `core/mock/mock_data.dart` — used when
///      the gallery provider returns nothing for this project. The
///      images carry no signedUrl so the tiles render with a fallback
///      placeholder (sand-coloured box + camera icon).
///   3. A small bundled list of stock farm photos for the demo `gv` /
///      `so` / `va` projects — keeps the visual story working until
///      `gallery_photos` rows exist in Supabase. See data sources guide
///      `docs/ops/data_sources_guide.md` (Photos sub-screen section).
class ProjectPhotosScreen extends ConsumerWidget {
  final String projectId;

  const ProjectPhotosScreen({required this.projectId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));
    final galleryAsync = ref.watch(galleryProvider);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: ArlColors.cream,
        surfaceTintColor: ArlColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.home);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Photos',
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              projectAsync.valueOrNull?.name ?? '',
              style: const TextStyle(
                color: ArlColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: Builder(builder: (context) {
        final photos = _resolvePhotos(
          gallery: galleryAsync.valueOrNull ?? const [],
          projectId: projectId,
        );

        if (photos.isEmpty) {
          return const _EmptyState();
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: photos.length,
          itemBuilder: (context, index) {
            final photo = photos[index];
            return _PhotoTile(
              photo: photo,
              heroTag: 'project-photo-$projectId-$index',
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierColor: Colors.black,
                    pageBuilder: (_, __, ___) => _FullscreenPhoto(
                      photo: photo,
                      heroTag: 'project-photo-$projectId-$index',
                    ),
                  ),
                );
              },
            );
          },
        );
      }),
    );
  }

  /// Picks the best available photo set, in order: real gallery rows
  /// filtered to this project → mock_data rows for this project →
  /// the bundled demo strip below. Always returns at least an empty list.
  List<_PhotoSrc> _resolvePhotos({
    required List<GalleryPhoto> gallery,
    required String projectId,
  }) {
    final id = projectId.replaceAll(RegExp(r'^demo:'), '').toLowerCase();

    // 1) Real photos that actually carry a signed URL for this project.
    final real = gallery
        .where((p) =>
            p.projectId.toLowerCase() == id && p.signedUrl.isNotEmpty)
        .map((p) => _PhotoSrc(url: p.signedUrl, caption: p.caption))
        .toList();
    if (real.isNotEmpty) return real;

    // 2) Mock photos from core/mock/mock_data.dart that carry a URL.
    final mocks = mockGalleryPhotos
        .where((m) =>
            m.projectId.toLowerCase() == id && (m.signedUrl?.isNotEmpty ?? false))
        .map((m) => _PhotoSrc(url: m.signedUrl!, caption: null))
        .toList();
    if (mocks.isNotEmpty) return mocks;

    // 3) Bundled stock farm photos so the demo projects always have a
    //    visible grid until `gallery_photos` rows show up in Supabase.
    return _bundled(id);
  }

  List<_PhotoSrc> _bundled(String id) {
    const gv = [
      'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1464226184884-fa280b87c399?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1591857177580-dc82b9ac4e1e?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1597595272404-ab0577dc6404?w=900&q=80&auto=format&fit=crop',
    ];
    const so = [
      'https://images.unsplash.com/photo-1559827260-dc66d52bef19?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1474481457074-eb16cbb3d8eb?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=900&q=80&auto=format&fit=crop',
    ];
    const va = [
      'https://images.unsplash.com/photo-1592982537447-7440770faae5?w=900&q=80&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=900&q=80&auto=format&fit=crop',
    ];

    final pick = id == 'gv'
        ? gv
        : id == 'so'
            ? so
            : id == 'va'
                ? va
                : gv;
    return pick.map((u) => _PhotoSrc(url: u, caption: null)).toList();
  }
}

class _PhotoTile extends StatelessWidget {
  final _PhotoSrc photo;
  final String heroTag;
  final VoidCallback onTap;

  const _PhotoTile({
    required this.photo,
    required this.heroTag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: ArlColors.sand,
              child: CachedNetworkImage(
                imageUrl: photo.url,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(),
                errorWidget: (_, __, ___) => _placeholder(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: ArlColors.sand,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_outlined,
          size: 36,
          color: ArlColors.muted,
        ),
      );
}

class _FullscreenPhoto extends StatelessWidget {
  final _PhotoSrc photo;
  final String heroTag;

  const _FullscreenPhoto({required this.photo, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: heroTag,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: photo.url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button — top-left.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.black.withOpacity(0.4),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 48,
              color: ArlColors.muted.withOpacity(0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'No photos yet',
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Daily photos from this project will appear here at 9 AM IST.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSrc {
  final String url;
  final String? caption;
  const _PhotoSrc({required this.url, this.caption});
}
