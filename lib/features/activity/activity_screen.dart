import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/async_value_widget.dart';
import 'package:arl_app/features/activity/activity_provider.dart';
import 'package:arl_app/features/activity/models/notification.dart';

// Mocks are used for the Activity History (timeline) tab only when the
// user is NOT signed in (design-preview / demo flow). Once signed in,
// the timeline shows an empty state until a real backend feed exists.
import 'package:arl_app/core/mock/mock_data.dart'
    show MockTimelineEvent, mockTimelineEvents;

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
        ? 'Payouts & operational events'
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No notifications yet.',
            style: TextStyle(color: ArlColors.muted, fontSize: 12),
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
      default:
        return Icons.description_outlined;
    }
  }

  String? _ctaRouteFromMetadata(Map<String, dynamic>? m) {
    if (m == null) return null;
    return (m['cta_route'] ?? m['route']) as String?;
  }

  String? _ctaLabelFromMetadata(Map<String, dynamic>? m, String type) {
    if (m != null && m['cta_label'] is String) return m['cta_label'] as String;
    switch (type) {
      case 'photo':
        return 'View Gallery';
      case 'payout':
        return 'View Details';
      case 'milestone':
        return 'View Project';
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
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
                if (ctaLabel != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed:
                        ctaRoute != null ? () => context.push(ctaRoute) : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      backgroundColor: tint.withValues(alpha: 0.12),
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline / History view — backed by mocks for the unauthenticated
// design-preview flow only. Signed-in users see an empty state until a
// real activity feed is wired up; we never render demo events on top
// of a live session.
// ─────────────────────────────────────────────────────────────────────────────
class _TimelineView extends StatelessWidget {
  final String filter;
  final ValueChanged<String> onFilter;
  const _TimelineView({required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = SessionManager.isLoggedIn;

    final items = isLoggedIn
        ? const <MockTimelineEvent>[]
        : (mockTimelineEvents
            .where((e) => filter == 'all' || e.type == filter)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)));

    final monthFmt = DateFormat('MMMM yyyy');
    final groups = <String, List<MockTimelineEvent>>{};
    for (final ev in items) {
      groups.putIfAbsent(monthFmt.format(ev.date), () => []).add(ev);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in const [
                ['all', 'All'],
                ['operational', 'Operational'],
                ['payout', 'Payouts'],
              ])
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
                Icon(
                  Icons.history,
                  size: 36,
                  color: ArlColors.muted.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No activity yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Payouts and operational events will appear here once they sync.',
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
  final MockTimelineEvent event;
  const _TimelineItem({required this.event});

  @override
  Widget build(BuildContext context) {
    final dotColor = event.type == 'payout' ? ArlColors.gold : ArlColors.accent;
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
                  color: dotColor.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: ArlColors.sand),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
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
                        '+₹${event.amount!.toStringAsFixed(0)}',
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
                  style: const TextStyle(color: ArlColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  event.utr != null
                      ? '${dateFmt.format(event.date)} · UTR: ${event.utr}'
                      : dateFmt.format(event.date),
                  style: const TextStyle(color: ArlColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
