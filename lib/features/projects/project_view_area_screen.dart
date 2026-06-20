import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/projects/projects_provider.dart';
// GrowingTechSection widget removed from this screen but the
// `GrowingTech` model is still used to keep the per-project crop list
// keying consistent — that's why the import stays.
import 'package:arl_app/features/projects/widgets/growing_tech_section.dart';

/// "View Area" — the rich geography + property sub-screen pushed from
/// the project detail page. Mirrors `#page-location` in the HTML mockup
/// with the v3 R3 ordering:
///
///   1. AppBar (back + project name)
///   2. Map preview (SVG-styled container with circular overlay)
///   3. "Within 5 km of <town>" tag
///   4. GrowingTechSection (moved out of detail)
///   5. Crops Grown bullets
///   6. Climate Control summary (year-round, temp, humidity)
///   7. Acreage / Property (total + cultivated + infra line)
///   8. Caption — exact address shared post-allocation
///
/// All location-specific values are mocked for v1 — the columns are
/// documented in `docs/ops/data_sources_guide.md` and will switch to
/// Supabase reads once the migration lands.
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
                    townTag: 'Within 5 km of ${profile.nearestTown}',
                    areaLabel: profile.region,
                  ),
                  const SizedBox(height: 16),
                  // Growing Technology section removed per UX call — the
                  // tech specs are covered during the onboarding call.
                  _CropsCard(crops: profile.crops),
                  const SizedBox(height: 16),
                  _ClimateCard(
                    cycle: profile.climateCycle,
                    temp: profile.climateTemp,
                    humidity: profile.climateHumidity,
                  ),
                  const SizedBox(height: 16),
                  _AcreageCard(
                    totalAcres: profile.totalAcres,
                    cultivatedAcres: profile.cultivatedAcres,
                    infrastructure: profile.infrastructure,
                  ),
                  const SizedBox(height: 16),
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

/// Map preview — SVG-styled placeholder with a translucent radius
/// circle, "1 km" scale chip, and a region tag overlay. No Google
/// Maps key required.
class _MapPreview extends StatelessWidget {
  final String townTag;
  final String areaLabel;

  const _MapPreview({required this.townTag, required this.areaLabel});

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
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Terrain-style gradient
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.9,
                        colors: [
                          Color(0xFFE8ECD9),
                          Color(0xFFCDD6C7),
                        ],
                      ),
                    ),
                  ),
                  // Faint grid overlay to mimic the SVG map look.
                  const _GridOverlay(),
                  // Translucent circle marking approximate area (5 km).
                  Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: ArlColors.accent.withOpacity(0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ArlColors.accent.withOpacity(0.9),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // 5 km scale chip — top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            child: Divider(
                              color: ArlColors.charcoal,
                              thickness: 2,
                              height: 2,
                            ),
                          ),
                          SizedBox(width: 4),
                          Text(
                            '5 km',
                            style: TextStyle(
                              color: ArlColors.charcoal,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                ],
              ),
            ),
          ),
          // Caption strip under the map
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

/// Faint cross-hatch grid drawn over the terrain gradient — keeps the
/// map placeholder from looking flat without pulling in a tile-server.
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(), size: Size.infinite);
  }
}

class _GridPainter extends CustomPainter {
  static final _paint = Paint()
    ..color = const Color(0xFFCDD6C7).withOpacity(0.55)
    ..strokeWidth = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CropsCard extends StatelessWidget {
  final List<_CropEntry> crops;
  const _CropsCard({required this.crops});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.spa_outlined,
      iconColor: ArlColors.accent,
      title: 'Crops Grown',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: crops.map((c) {
          final isPrimary = c.primary;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isPrimary
                  ? ArlColors.accent.withOpacity(0.12)
                  : ArlColors.sand,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.emoji.isNotEmpty) ...[
                  Text(c.emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                ],
                Text(
                  c.name,
                  style: TextStyle(
                    color: isPrimary
                        ? ArlColors.accent
                        : ArlColors.charcoal,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isPrimary) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: ArlColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Primary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ClimateCard extends StatelessWidget {
  final String cycle;
  final String temp;
  final String humidity;

  const _ClimateCard({
    required this.cycle,
    required this.temp,
    required this.humidity,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.thermostat,
      iconColor: ArlColors.primary,
      title: 'Climate Control',
      child: Row(
        children: [
          Expanded(child: _ClimateTile(label: 'Growing', value: cycle)),
          const SizedBox(width: 8),
          Expanded(child: _ClimateTile(label: 'Temp', value: temp)),
          const SizedBox(width: 8),
          Expanded(child: _ClimateTile(label: 'Humidity', value: humidity)),
        ],
      ),
    );
  }
}

class _ClimateTile extends StatelessWidget {
  final String label;
  final String value;
  const _ClimateTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcreageCard extends StatelessWidget {
  final String totalAcres;
  final String cultivatedAcres;
  final String infrastructure;

  const _AcreageCard({
    required this.totalAcres,
    required this.cultivatedAcres,
    required this.infrastructure,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.layers_outlined,
      iconColor: ArlColors.primary,
      title: 'Property',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PropTile(
                  label: 'Total Area',
                  value: totalAcres,
                  emphasize: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PropTile(
                  label: 'Under Cultivation',
                  value: cultivatedAcres,
                  emphasize: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ArlColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warehouse_outlined,
                    size: 14, color: ArlColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    infrastructure,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 12,
                      height: 1.4,
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
          color: emphasize
              ? ArlColors.accent.withOpacity(0.3)
              : ArlColors.sand,
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
          const Icon(Icons.shield_outlined,
              size: 16, color: ArlColors.primary),
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
/// climate_summary, acreage_acres, cultivated_acres, infra_summary...).
class _ViewAreaProfile {
  final String nearestTown;
  final String region;
  final List<_CropEntry> crops;
  final String climateCycle;
  final String climateTemp;
  final String climateHumidity;
  final String totalAcres;
  final String cultivatedAcres;
  final String infrastructure;

  const _ViewAreaProfile({
    required this.nearestTown,
    required this.region,
    required this.crops,
    required this.climateCycle,
    required this.climateTemp,
    required this.climateHumidity,
    required this.totalAcres,
    required this.cultivatedAcres,
    required this.infrastructure,
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
        climateCycle: 'N/A',
        climateTemp: 'N/A',
        climateHumidity: 'N/A',
        totalAcres: '8.2 acres',
        cultivatedAcres: '5.4 acres',
        infrastructure:
            'Polyhouse infrastructure with shade nets & vertical racking',
      );
    }

    if (id == 'so' || ini == 'SO') {
      return _ViewAreaProfile(
        nearestTown: 'Niphad',
        region: fallbackLocation.isNotEmpty
            ? fallbackLocation
            : 'Nashik Region, Maharashtra',
        crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
        climateCycle: 'N/A',
        climateTemp: 'N/A',
        climateHumidity: 'N/A',
        totalAcres: '12.4 acres',
        cultivatedAcres: '9.1 acres',
        infrastructure:
            'Hydroponic NFT + DWC channels with trellised vine rows',
      );
    }

    if (id == 'va' || ini == 'VA') {
      return _ViewAreaProfile(
        nearestTown: 'Lonavala',
        region: fallbackLocation.isNotEmpty
            ? fallbackLocation
            : 'Lonavala Region, Maharashtra',
        crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
        climateCycle: 'N/A',
        climateTemp: 'N/A',
        climateHumidity: 'N/A',
        totalAcres: '6.0 acres',
        cultivatedAcres: '3.2 acres',
        infrastructure:
            'Vertical aeroponic towers in climate-controlled polyhouse',
      );
    }

    // Generic fallback — shown for any project we don't have a profile for.
    return _ViewAreaProfile(
      nearestTown: 'the project town',
      region: fallbackLocation.isNotEmpty
          ? fallbackLocation
          : 'Project Region',
      crops: const [_CropEntry(emoji: '', name: 'TBD', primary: true)],
      climateCycle: 'N/A',
      climateTemp: 'N/A',
      climateHumidity: 'N/A',
      totalAcres: 'TBD',
      cultivatedAcres: 'TBD',
      infrastructure:
          'Controlled environment agriculture with smart irrigation',
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
