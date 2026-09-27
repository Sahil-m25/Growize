import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/projects/projects_provider.dart';
// GrowingTechSection widget removed from this screen but the
// `GrowingTech` model is still used to keep the per-project crop list
// keying consistent — that's why the import stays.
import 'package:arl_app/features/projects/widgets/growing_tech_section.dart';

/// "View Area" — approximate farm location and property basics, pushed
/// from the project detail page:
///
///   1. Map: OpenStreetMap tiles centred on the project's reference
///      point (projects.latitude/longitude) with a 5 km radius circle.
///   2. Property: total area from projects.acreage_acres.
///   3. Caption — exact address shared post-allocation.
///
/// Falls back to the mock profile for demo projects without coordinates.
class _ProjectGeo {
  final double? lat;
  final double? lng;
  final double? acres;
  final String? town;
  final String? state;
  const _ProjectGeo({this.lat, this.lng, this.acres, this.town, this.state});
}

double? _num(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

final _projectGeoProvider =
    FutureProvider.family<_ProjectGeo?, String>((ref, id) async {
  final client = ArlSupabase.client;
  if (client == null || id.startsWith('demo:')) return null;
  try {
    final row = await client
        .from('projects')
        .select('latitude, longitude, acreage_acres, city, state')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return _ProjectGeo(
      lat: _num(row['latitude']),
      lng: _num(row['longitude']),
      acres: _num(row['acreage_acres']),
      town: row['city'] as String?,
      state: row['state'] as String?,
    );
  } catch (_) {
    return null;
  }
});

/// Reference point used until a project has its own coordinates
/// (Talakad, Karnataka).
const _defaultLat = 12.1810843;
const _defaultLng = 77.0391754;

class ProjectViewAreaScreen extends ConsumerWidget {
  final String projectId;

  const ProjectViewAreaScreen({required this.projectId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return projectAsync.when(
      loading: () => const Scaffold(
        backgroundColor: ArlColors.cream,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Scaffold(
        backgroundColor: ArlColors.cream,
        body: Center(child: CircularProgressIndicator()),
      ),
      data: (project) {
        if (project == null) {
          return const Scaffold(
            backgroundColor: ArlColors.cream,
            body: Center(child: Text('Project not found')),
          );
        }

        final geo = ref.watch(_projectGeoProvider(project.id)).valueOrNull;
        final profile = _ViewAreaProfile.forProject(
          projectId: project.id,
          fallbackLocation: project.location,
          initials: project.initials,
        );

        // GrowingTech model still referenced for forward compat — the
        // visible tech section was removed from this screen per UX call.
        // ignore: unused_local_variable
        final tech = GrowingTech.forProject(
          projectId: project.id,
          initials: project.initials,
        );

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
                Text(
                  project.name,
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'View Area',
                  style: TextStyle(
                    color: ArlColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            centerTitle: false,
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MapPreview(
                    lat: geo?.lat ?? _defaultLat,
                    lng: geo?.lng ?? _defaultLng,
                    townTag:
                        'Within 5 km of ${geo?.town ?? profile.nearestTown}',
                    areaLabel: geo?.town != null
                        ? [geo!.town, geo.state]
                            .whereType<String>()
                            .where((e) => e.isNotEmpty)
                            .join(', ')
                        : profile.region,
                  ),
                  const SizedBox(height: 16),
                  if (geo?.acres != null || profile.totalAcres != 'TBD') ...[
                    _AcreageCard(
                      totalAcres: geo?.acres != null
                          ? '${_trimAcres(geo!.acres!)} acres'
                          : profile.totalAcres,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const _Caption(
                    text:
                        'Approximate location — exact address shared post-allocation.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _trimAcres(double a) => a == a.roundToDouble()
    ? a.toStringAsFixed(0)
    : a.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

/// Approximate-area map: OpenStreetMap raster tiles centred on the
/// reference point, with a translucent 5 km radius circle. No API key.
class _MapPreview extends StatelessWidget {
  final double lat;
  final double lng;
  final String townTag;
  final String areaLabel;

  const _MapPreview({
    required this.lat,
    required this.lng,
    required this.townTag,
    required this.areaLabel,
  });

  static const _radiusMeters = 5000.0;

  /// Opens Google Maps on the area (not a pin): centred on the reference
  /// point at a zoom that shows roughly the same 5 km neighbourhood.
  Future<void> _openMaps() async {
    final uri = Uri.parse(
        'https://www.google.com/maps/@?api=1&map_action=map&center=$lat,$lng&zoom=12&basemap=satellite');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _openMaps,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: LayoutBuilder(builder: (context, box) {
                    final w = box.maxWidth, h = box.maxHeight;
                    // Pick the closest zoom where the 5 km circle fills most
                    // of the shorter side without spilling out.
                    final latRad = lat * math.pi / 180;
                    int z = 13;
                    double mpp(int z) =>
                        156543.03392 * math.cos(latRad) / math.pow(2, z);
                    while (z > 8 &&
                        _radiusMeters / mpp(z) > math.min(w, h) * 0.42) {
                      z--;
                    }
                    final radiusPx = _radiusMeters / mpp(z);
                    final n = math.pow(2, z).toDouble();
                    final cx = (lng + 180) / 360 * n * 256;
                    final cy = (1 -
                            math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                                math.pi) /
                        2 *
                        n *
                        256;
                    final left = cx - w / 2, top = cy - h / 2;
                    final tiles = <Widget>[];
                    for (int tx = (left / 256).floor();
                        tx <= ((left + w) / 256).floor();
                        tx++) {
                      for (int ty = (top / 256).floor();
                          ty <= ((top + h) / 256).floor();
                          ty++) {
                        if (ty < 0 || ty >= n) continue;
                        final wx = ((tx % n) + n) % n;
                        tiles.add(Positioned(
                          left: tx * 256 - left,
                          top: ty * 256 - top,
                          width: 256,
                          height: 256,
                          child: Image.network(
                            'https://tile.openstreetmap.org/$z/${wx.toInt()}/$ty.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFFE8ECD9)),
                          ),
                        ));
                      }
                    }
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                            child: Container(color: const Color(0xFFE8ECD9))),
                        ...tiles,
                        // 5 km radius circle
                        Positioned(
                          left: w / 2 - radiusPx,
                          top: h / 2 - radiusPx,
                          width: radiusPx * 2,
                          height: radiusPx * 2,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: ArlColors.accent.withOpacity(0.16),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ArlColors.accent.withOpacity(0.9),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Radius chip — top-right
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '5 km radius · Open in Maps ↗',
                              style: TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Town tag — bottom-left
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: ArlColors.accent.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  townTag,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Attribution — required by the OSM tile policy
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            color: Colors.white.withOpacity(0.8),
                            child: const Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(
                                  fontSize: 8, color: ArlColors.charcoal),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: ArlColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    areaLabel,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcreageCard extends StatelessWidget {
  final String totalAcres;

  const _AcreageCard({required this.totalAcres});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.layers_outlined,
      iconColor: ArlColors.primary,
      title: 'Property',
      child: _PropTile(
        label: 'Total Area',
        value: totalAcres,
        emphasize: true,
      ),
    );
  }
}

class _PropTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _PropTile({
    required this.label,
    required this.value,
    required this.emphasize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: emphasize
            ? ArlColors.accent.withOpacity(0.1)
            : ArlColors.sand.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize ? ArlColors.accent.withOpacity(0.3) : ArlColors.sand,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? ArlColors.accent : ArlColors.charcoal,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  final String text;
  const _Caption({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArlColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ArlColors.primary.withOpacity(0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 16, color: ArlColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: ArlColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight bag of mock copy used to populate the View Area page.
/// Real values come from new `projects.*` columns documented in
/// `docs/ops/data_sources_guide.md` (growing_method, crops_grown,
/// acreage_acres, latitude, longitude, city, state).
class _ViewAreaProfile {
  final String nearestTown;
  final String region;
  final List<_CropEntry> crops;
  final String totalAcres;

  const _ViewAreaProfile({
    required this.nearestTown,
    required this.region,
    required this.crops,
    required this.totalAcres,
  });

  static _ViewAreaProfile forProject({
    required String projectId,
    required String fallbackLocation,
    required String initials,
  }) {
    final id = projectId.replaceAll(RegExp(r'^demo:'), '').toLowerCase();
    final ini = initials.toUpperCase();

    if (id == 'gv' || ini == 'GV') {
      return _ViewAreaProfile(
        nearestTown: 'Manchar',
        region: fallbackLocation.isNotEmpty
            ? fallbackLocation
            : 'Pune Region, Maharashtra',
        crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
        totalAcres: '8.2 acres',
      );
    }

    if (id == 'so' || ini == 'SO') {
      return _ViewAreaProfile(
        nearestTown: 'Niphad',
        region: fallbackLocation.isNotEmpty
            ? fallbackLocation
            : 'Nashik Region, Maharashtra',
        crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
        totalAcres: '12.4 acres',
      );
    }

    if (id == 'va' || ini == 'VA') {
      return _ViewAreaProfile(
        nearestTown: 'Lonavala',
        region: fallbackLocation.isNotEmpty
            ? fallbackLocation
            : 'Lonavala Region, Maharashtra',
        crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
        totalAcres: '6.0 acres',
      );
    }

    // Generic fallback — shown for any project we don't have a profile for.
    return _ViewAreaProfile(
      nearestTown: 'the project town',
      region: fallbackLocation.isNotEmpty ? fallbackLocation : 'Project Region',
      crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
      totalAcres: 'TBD',
    );
  }
}

class _CropEntry {
  final String emoji;
  final String name;
  final bool primary;

  const _CropEntry({
    required this.emoji,
    required this.name,
    this.primary = false,
  });
}
