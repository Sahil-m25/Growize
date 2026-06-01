import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/arl_colors.dart';

/// Hero banner used at the top of each project detail screen — mirrors
/// the v2 hero block in `page-projects` (200px tall photo, dark gradient
/// from bottom, name overlay with text-shadow, optional tier badge
/// top-right). Falls back to a sand-coloured container with the project
/// initials when [imageUrl] is null or fails to load.
class ProjectHeroBanner extends StatelessWidget {
  final String name;
  final String? location;
  final String? imageUrl;
  final String? tierBadge;
  final String? initials;
  final Color? fallbackTint;
  final VoidCallback? onBack;

  const ProjectHeroBanner({
    super.key,
    required this.name,
    this.location,
    this.imageUrl,
    this.tierBadge,
    this.initials,
    this.fallbackTint,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 200 + topInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: photo or sand-coloured fallback
          if (hasImage)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _fallback(),
              errorWidget: (_, __, ___) => _fallback(),
            )
          else
            _fallback(),

          // Subtle dark gradient bottom-to-top so the name pops.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),

          // Back button — top-left (white circle on glass).
          if (onBack != null)
            Positioned(
              top: topInset + 12,
              left: 12,
              child: Material(
                color: Colors.white.withValues(alpha: 0.2),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onBack,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          // Tier badge — top-right.
          if (tierBadge != null && tierBadge!.isNotEmpty)
            Positioned(
              top: topInset + 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      color: ArlColors.goldLight,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tierBadge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Project name + location — bottom-left, white with text-shadow.
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Color(0xA6000000), // 65% black
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (location != null && location!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            shadows: const [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: fallbackTint ?? ArlColors.sand,
      alignment: Alignment.center,
      child: initials == null
          ? const Icon(
              Icons.eco_outlined,
              color: ArlColors.muted,
              size: 56,
            )
          : Text(
              initials!,
              style: TextStyle(
                color: ArlColors.primary.withValues(alpha: 0.4),
                fontSize: 56,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
    );
  }
}
