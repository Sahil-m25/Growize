import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/activity/activity_provider.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';

class ArlAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ArlAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Bell glows (gold dot) only when there's at least 1 unread
    // notification — otherwise the icon stands alone so the user
    // doesn't see a persistent "you have something" cue.
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final hasUnread = unread > 0;

    return Container(
      decoration: const BoxDecoration(
        color: ArlColors.cream,
        border: Border(bottom: BorderSide(color: Color(0xFFD4D2B4), width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Wordmark asset is the tightly-cropped version
                // (tools/crop_logo.py removes the transparent + white
                // padding from the source). With the padding gone we
                // can use BoxFit.contain at the natural wordmark
                // aspect ratio (~3.35:1) and it fills the header
                // height almost entirely with no stretch and no crop.
                // Flexible lets it shrink before pushing the buttons
                // off-screen on narrow phones.
                // Logo sized at 60% of header glyph height (34px tall in a 56px header)
                // per UAT feedback rounds 1 + 2 — original was 56px, first cut took it to
                // 42px (75%), this further 20% reduction lands at 34px.
                Flexible(
                  key: TourKeys.appBarLogo,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 113),
                    child: SizedBox(
                      height: 34,
                      child: Image.asset(
                        'assets/images/arl_logo_wordmark.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        filterQuality: FilterQuality.high,
                        cacheHeight: (34 * dpr).round(),
                        isAntiAlias: true,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _CircleButton(
                      key: TourKeys.notificationBell,
                      onTap: () => context.push(RouteNames.activity),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            hasUnread
                                ? Icons.notifications_active
                                : Icons.notifications_outlined,
                            color: hasUnread
                                ? ArlColors.gold
                                : ArlColors.charcoal,
                            size: 22,
                          ),
                          if (hasUnread)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: ArlColors.earth,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: ArlColors.cream,
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  unread > 9 ? '9+' : '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      key: TourKeys.profileAvatar,
                      onTap: () => context.push(RouteNames.profile),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ArlColors.cream,
                          border: Border.all(color: ArlColors.gold, width: 2),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: ArlColors.primary,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _avatarInitials(ref),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Initials shown in the avatar circle — derived live from the
  /// signed-in investor's name, with a fallback to the auth user's
  /// email prefix so we never display a stale "SK" placeholder.
  String _avatarInitials(WidgetRef ref) {
    final investor = ref.watch(currentInvestorProvider).valueOrNull;
    final name = (investor?['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return _initialsFrom(name);

    final email = ArlSupabase.client?.auth.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      return _initialsFrom(email.split('@').first.replaceAll('.', ' '));
    }
    return '–';
  }

  static String _initialsFrom(String source) {
    final parts =
        source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '–';
    if (parts.length == 1) {
      final single = parts.first;
      return single.length >= 2
          ? single.substring(0, 2).toUpperCase()
          : single.toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    );
  }
}
