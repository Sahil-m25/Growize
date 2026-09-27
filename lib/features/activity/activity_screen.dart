import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/utils/money.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/activity/activity_provider.dart';
import 'package:arl_app/features/activity/models/notification.dart';

import 'package:arl_app/features/activity/activity_timeline.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _showHistory = false;
  String _filter = 'all'; // 'all' | 'operational' | 'payout'

  void _toggleView() => setState(() => _showHistory = !_showHistory);

  Future<void> _markAllRead() async {
    await ref.read(activityRepositoryProvider).markAllRead();
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncNotifs = ref.watch(notificationsProvider);
    final notifs = asyncNotifs.valueOrNull ?? const <ArlNotification>[];
    final unread = notifs.where((n) => !n.isRead).length;
    final title = _showHistory ? 'Activity History' : 'Notifications';
    final subtitle = _showHistory
        ? 'Investments, payouts & farm updates'
        : '$unread unread alert${unread == 1 ? '' : 's'}';

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
            child: Material(
              color: ArlColors.sand,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: _toggleView,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showHistory ? Icons.notifications_none : Icons.history,
                        size: 14,
                        color: ArlColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showHistory ? 'Notifications' : 'History',
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _showHistory
          ? _TimelineView(
              filter: _filter,
              onFilter: (f) => setState(() => _filter = f),
            )
          : AsyncValueWidget(
              value: asyncNotifs,
              onRetry: () => ref.invalidate(notificationsProvider),
              data: (list) =>
                  _NotifView(notifs: list, onMarkAllRead: _markAllRead),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications view
// ─────────────────────────────────────────────────────────────────────────────
class _NotifView extends StatelessWidget {
  final List<ArlNotification> notifs;
  final VoidCallback onMarkAllRead;
  const _NotifView({required this.notifs, required this.onMarkAllRead});

  @override
  Widget build(BuildContext context) {
    if (notifs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 36,
                color: ArlColors.muted.withOpacity(0.6),
              ),
              const SizedBox(height: 12),
              const Text(
                'No notifications yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Payout and operational alerts will appear here as your projects update.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT',
              style: TextStyle(
                color: ArlColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.7,
              ),
            ),
            TextButton(
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: ArlColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final n in notifs) ...[
          _NotifCard(notif: n),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _NotifCard extends StatelessWidget {
  final ArlNotification notif;
  const _NotifCard({required this.notif});

  Color _tint(String t) {
    switch (t) {
      case 'warning':
        return ArlColors.earth;
      case 'success':
        return ArlColors.accent;
      case 'payout':
        return ArlColors.gold;
      case 'milestone':
        return ArlColors.accent;
      default:
        return ArlColors.primary;
    }
  }

  IconData _icon(String t) {
    switch (t) {
      case 'warning':
        return Icons.error_outline;
      case 'success':
        return Icons.image_outlined;
      case 'payout':
        return Icons.account_balance_wallet_outlined;
      case 'milestone':
        return Icons.flag_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  /// Optional milestone photo, written by the migration-068 trigger from
  /// `project_phases.image_url`. Absent for every notification type that
  /// has no picture, which is most of them.
  String? _imageFromMetadata(Map<String, dynamic>? m) {
    final v = m?['image_url'];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  String? _ctaRouteFromMetadata(Map<String, dynamic>? m) {
    if (m == null) return null;
    final r = m['cta_route'] ?? m['route'];
    // Only accept internal app paths; anything else renders no CTA.
    return (r is String && r.startsWith('/')) ? r : null;
  }

  String? _ctaLabelFromMetadata(Map<String, dynamic>? m, String type) {
    if (m != null && m['cta_label'] is String) return m['cta_label'] as String;
    switch (type) {
      case 'photo':
        return 'View Gallery';
      case 'payout':
        return 'View Details';
      case 'milestone':
      case 'phase_update':
        return 'View update';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint(notif.displayType);
    final dateFmt = DateFormat('MMM dd · h:mm a');
    final ctaLabel = _ctaLabelFromMetadata(notif.metadata, notif.type);
    final ctaRoute = _ctaRouteFromMetadata(notif.metadata);
    final imageUrl = _imageFromMetadata(notif.metadata);

    // Whole card is tappable. Stage/update notifications open the farm
    // updates; everything else follows its own link.
    final target = (notif.type == 'phase_update' || notif.type == 'milestone')
        ? RouteNames.updates
        : ctaRoute;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tint.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child:
                Icon(_icon(notif.displayType), color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          fontWeight:
                              notif.isRead ? FontWeight.w600 : FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      dateFmt.format(notif.createdAt),
                      style:
                          const TextStyle(color: ArlColors.muted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notif.body,
                  style: const TextStyle(color: ArlColors.muted, fontSize: 11),
                ),
                if (imageUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        // A milestone card must still read correctly when
                        // the photo is slow or gone — never leave a broken
                        // box or a stretched placeholder in the feed.
                        placeholder: (_, __) => Container(
                          color: tint.withOpacity(0.12),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
                // No route -> no button (was a dead, disabled CTA).
                if (ctaLabel != null && target != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => context.push(target),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      backgroundColor: tint.withOpacity(0.12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      ctaLabel,
                      style: TextStyle(
                        color: tint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!notif.isRead)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => context.push(target),
        child: card,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History view — the investor's own timeline from real records:
// investments, payouts credited and farm updates. Demo mocks only in the
// signed-out design preview.
// ─────────────────────────────────────────────────────────────────────────────
class _TimelineView extends ConsumerWidget {
  final String filter;
  final ValueChanged<String> onFilter;
  const _TimelineView({required this.filter, required this.onFilter});

  static const _filters = [
    ['all', 'All'],
    ['farm', 'Farm updates'],
    ['payout', 'Payouts'],
    ['investment', 'Investments'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = SessionManager.isLoggedIn;
    final async = isLoggedIn
        ? ref.watch(activityTimelineProvider)
        : AsyncValue.data(demoTimeline());

    if (async.isLoading && !async.hasValue) {
      return const Center(
          child: CircularProgressIndicator(color: ArlColors.primary));
    }
    final items = (async.valueOrNull ?? const <TimelineEvent>[])
        .where((e) => filter == 'all' || e.type == filter)
        .toList();

    final monthFmt = DateFormat('MMMM yyyy');
    final groups = <String, List<TimelineEvent>>{};
    for (final ev in items) {
      groups.putIfAbsent(monthFmt.format(ev.date), () => []).add(ev);
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(activityTimelineProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      label: f[1],
                      selected: filter == f[0],
                      onTap: () => onFilter(f[0]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.history,
                      size: 36, color: ArlColors.muted.withOpacity(0.6)),
                  const SizedBox(height: 12),
                  const Text(
                    'Nothing here yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your investments, payouts and farm updates build up here over time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ArlColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  color: ArlColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            for (final ev in entry.value) ...[
              _TimelineItem(event: ev),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ArlColors.primary : ArlColors.sand,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : ArlColors.charcoal,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final TimelineEvent event;
  const _TimelineItem({required this.event});

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (event.type) {
      'payout' => ArlColors.gold,
      'investment' => ArlColors.primary,
      _ => ArlColors.accent,
    };
    final dateFmt = DateFormat('MMM dd, yyyy');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, right: 10),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: dotColor.withOpacity(0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap:
                event.route == null ? null : () => context.push(event.route!),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: ArlColors.sand),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (event.amount != null)
                        Text(
                          '+${Money.inr(event.amount!, inline: true)}',
                          style: const TextStyle(
                            color: ArlColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.subtitle,
                    style:
                        const TextStyle(color: ArlColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.utr != null
                        ? '${dateFmt.format(event.date)} · UTR: ${event.utr}'
                        : dateFmt.format(event.date),
                    style:
                        const TextStyle(color: ArlColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
