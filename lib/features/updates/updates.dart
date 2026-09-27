import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/auth/auth_provider.dart';
import 'package:arl_app/features/projects/models/project_update.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Farm updates across every project the investor holds.
///
/// Updates used to live only inside each project page. They now surface on
/// Home (latest three), on a full Updates page, and each one opens its own
/// detail page, which notifications also link to. RLS on project_updates
/// already limits rows to the investor's own projects.
final allUpdatesProvider = FutureProvider<List<ProjectUpdate>>((ref) async {
  ref.watch(authStateProvider);
  final client = ArlSupabase.client;
  if (client == null || !SessionManager.isLoggedIn) return const [];
  try {
    final rows = await client
        .from('project_updates')
        .select()
        .order('update_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((r) => ProjectUpdate.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  } catch (_) {
    return const [];
  }
});

/// project id -> project name, for the small label on each update.
final _projectNamesProvider = Provider<Map<String, String>>((ref) {
  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  return {for (final p in projects) p.id: p.name};
});

String _date(DateTime d) => DateFormat('d MMM yyyy').format(d);

BoxDecoration _card() => BoxDecoration(
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
    );

Widget _datePill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ArlColors.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );

Widget _image(String url, {double radius = 10}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : Container(color: ArlColors.sand),
        errorBuilder: (_, __, ___) => Container(color: ArlColors.sand),
      ),
    );

bool _hasImage(ProjectUpdate u) => (u.imageUrl ?? '').trim().isNotEmpty;

// ── Home card ────────────────────────────────────────────────────────────

/// "Latest updates" on Home: the three newest updates, each tappable,
/// plus "See all". Hidden entirely when there are no updates yet.
class HomeUpdatesCard extends ConsumerWidget {
  const HomeUpdatesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(allUpdatesProvider).valueOrNull ?? const [];
    if (updates.isEmpty) return const SizedBox.shrink();
    final names = ref.watch(_projectNamesProvider);
    final latest = updates.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Latest updates',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(RouteNames.updates),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: ArlColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < latest.length; i++) ...[
            _CompactUpdateRow(
              update: latest[i],
              projectName: names[latest[i].projectId],
            ),
            if (i != latest.length - 1)
              const Divider(height: 18, color: ArlColors.sand),
          ],
        ],
      ),
    );
  }
}

class _CompactUpdateRow extends StatelessWidget {
  final ProjectUpdate update;
  final String? projectName;
  const _CompactUpdateRow({required this.update, this.projectName});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('${RouteNames.updates}/${update.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasImage(update)) ...[
            SizedBox(width: 56, height: 56, child: _image(update.imageUrl!)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [_date(update.updateDate), if (projectName != null) projectName!]
                      .join(' · '),
                  style: const TextStyle(color: ArlColors.muted, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  update.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  update.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 6, top: 14),
            child: Icon(Icons.chevron_right, size: 18, color: ArlColors.muted),
          ),
        ],
      ),
    );
  }
}

// ── Updates page ─────────────────────────────────────────────────────────

AppBar _appBar(BuildContext context, String title) => AppBar(
      backgroundColor: ArlColors.cream,
      surfaceTintColor: ArlColors.cream,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
        onPressed: () =>
            context.canPop() ? context.pop() : context.go(RouteNames.home),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: false,
    );

/// Every farm update, newest first. Each card opens its detail page.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allUpdatesProvider);
    final names = ref.watch(_projectNamesProvider);
    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: _appBar(context, 'Farm updates'),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ArlColors.primary),
        ),
        error: (_, __) => const _Empty(text: 'Could not load updates.'),
        data: (updates) {
          if (updates.isEmpty) {
            return const _Empty(text: 'No updates yet. Check back soon.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allUpdatesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: updates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final u = updates[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => context.push('${RouteNames.updates}/${u.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _card(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _datePill(_date(u.updateDate)),
                            if (names[u.projectId] != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  names[u.projectId]!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: ArlColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          u.title,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          u.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ArlColors.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        if (_hasImage(u)) ...[
                          const SizedBox(height: 10),
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _image(u.imageUrl!),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// One update, in full. Tap the photo to zoom.
class UpdateDetailScreen extends ConsumerWidget {
  final String updateId;
  const UpdateDetailScreen({required this.updateId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allUpdatesProvider);
    final names = ref.watch(_projectNamesProvider);
    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: _appBar(context, 'Update'),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ArlColors.primary),
        ),
        error: (_, __) => const _Empty(text: 'Could not load this update.'),
        data: (updates) {
          ProjectUpdate? u;
          for (final x in updates) {
            if (x.id == updateId) u = x;
          }
          if (u == null) {
            return const _Empty(text: 'This update is no longer available.');
          }
          final update = u;
          final project = names[update.projectId];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _datePill(_date(update.updateDate)),
                        if (project != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              project,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ArlColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      update.title,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      update.body,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (_hasImage(update)) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ZoomImage(url: update.imageUrl!),
                          ),
                        ),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _image(update.imageUrl!, radius: 12),
                        ),
                      ),
                    ],
                    if (project != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => context.go(
                              '${RouteNames.projects}/${update.projectId}'),
                          child: Text(
                            'View $project',
                            style: const TextStyle(
                              color: ArlColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ZoomImage extends StatelessWidget {
  final String url;
  const _ZoomImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ArlColors.muted, fontSize: 13),
          ),
        ),
      );
}
