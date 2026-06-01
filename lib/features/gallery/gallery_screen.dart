import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/gallery/gallery_provider.dart';
import 'package:arl_app/features/gallery/models/gallery_photo.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  // Group photos by date (YYYY-MM-DD key)
  Map<String, List<GalleryPhoto>> _groupByDate(List<GalleryPhoto> photos) {
    final map = <String, List<GalleryPhoto>>{};
    for (final p in photos) {
      final ts = p.takenAt ?? p.uploadedAt ?? DateTime.now();
      final key = DateFormat('yyyy-MM-dd').format(ts);
      map.putIfAbsent(key, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayFmt = DateFormat('EEE, d MMM yyyy');
    final asyncPhotos = ref.watch(galleryProvider);

    return Scaffold(
      backgroundColor: ArlColors.primary,
      appBar: AppBar(
        backgroundColor: ArlColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Daily 9:00 AM IST · Last 30 days',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: AsyncValueWidget(
        value: asyncPhotos,
        onRetry: () => ref.invalidate(galleryProvider),
        data: (photos) {
          if (photos.isEmpty) {
            return _empty();
          }
          final grouped = _groupByDate(photos);
          final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return Column(
            children: [
              Container(
                color: Colors.black.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        color: Colors.white.withValues(alpha: 0.6), size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'Photos captured daily at 9:00 AM IST',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, sectionIdx) {
                    final dateKey = sortedKeys[sectionIdx];
                    final dayPhotos = grouped[dateKey]!;
                    final date = DateTime.parse(dateKey);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  dayFmt.format(date),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: ArlColors.arlGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${dayPhotos.length} photo${dayPhotos.length > 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: dayPhotos.length,
                            itemBuilder: (context, photoIdx) {
                              return _PhotoTile(photo: dayPhotos[photoIdx], index: photoIdx);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 32, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(height: 10),
              Text(
                'No photos yet',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Daily photos appear here once your project is operational.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
}

class _PhotoTile extends StatelessWidget {
  final GalleryPhoto photo;
  final int index;
  const _PhotoTile({required this.photo, required this.index});

  @override
  Widget build(BuildContext context) {
    final hasUrl = photo.signedUrl.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: ArlColors.primary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasUrl)
              CachedNetworkImage(
                imageUrl: photo.signedUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 28,
                  ),
                ),
                errorWidget: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 28,
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 28,
                ),
              ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ),
            if (photo.isDemo)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: ArlColors.gold.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'Sample',
                    style: TextStyle(
                      color: Color(0xFF3C2E00),
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
