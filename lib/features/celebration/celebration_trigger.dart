import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/features/financials/financials_provider.dart';
import 'package:arl_app/features/financials/models/payout.dart';

import 'celebration_flag.dart';

/// Drives the first-payout celebration overlay.
///
/// T1 builds + wires this class. T4 will call [maybeShow] from
/// `home_screen` after the home tab finishes its first frame. Until then
/// no call site exists in product code — see `README_FOR_T4.md` in this
/// folder for the integration recipe.
abstract final class CelebrationTrigger {
  /// Checks gating conditions and, if eligible, pushes `/celebration`
  /// with the first payout's data. After the screen pops, persists the
  /// "seen" flag so it won't fire again.
  ///
  /// Gates:
  ///   1. `!CelebrationFlag.hasSeen()` — never re-show once dismissed.
  ///   2. `payouts.count > 0`          — must actually have a payout.
  ///
  /// Failures (network, missing context, etc.) silently no-op — the
  /// celebration is delightful but optional; never block app entry.
  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    if (await CelebrationFlag.hasSeen()) return;

    final List<Payout> payouts;
    try {
      payouts = await ref.read(payoutsProvider.future);
    } catch (_) {
      return;
    }
    if (payouts.isEmpty) return;

    // First payout chronologically — sort by date ascending and pick [0].
    final sorted = [...payouts]..sort((a, b) => a.date.compareTo(b.date));
    final first = sorted.first;

    if (!context.mounted) return;

    final query = <String, String>{
      'amount': first.amount.toString(),
      'project': first.projectName,
      'date': first.date.toIso8601String(),
    };
    final uri = Uri(path: '/celebration', queryParameters: query);

    await context.push(uri.toString());

    // After the celebration pops, persist the seen flag. (The "Maybe
    // later" link inside the screen also calls markSeen — this is
    // belt-and-suspenders for the "View in Financials" branch and for
    // back-button dismissals.)
    await CelebrationFlag.markSeen();
  }
}
