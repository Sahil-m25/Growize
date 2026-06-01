import 'package:flutter/widgets.dart';

/// Central registry of [GlobalKey]s consumed by the in-app tour overlay.
///
/// The overlay never reaches into screen state to find its targets; it
/// looks up a key here, asks the key's [RenderBox] for its global rect,
/// then draws a cutout + arrow over that rect. Screens only need to
/// attach the matching key to the widget they want highlighted — no
/// restructuring required.
///
/// Naming convention: `<screen><target>` so a glance at the field
/// instantly tells you where the widget lives.
class TourKeys {
  TourKeys._();

  // ── App bar (lives on every shell route) ────────────────────────────
  static final GlobalKey appBarLogo = GlobalKey(debugLabel: 'tour.appBarLogo');
  static final GlobalKey notificationBell =
      GlobalKey(debugLabel: 'tour.notificationBell');
  static final GlobalKey profileAvatar =
      GlobalKey(debugLabel: 'tour.profileAvatar');

  // ── Home screen ─────────────────────────────────────────────────────
  static final GlobalKey portfolioCard =
      GlobalKey(debugLabel: 'tour.portfolioCard');
  static final GlobalKey projectProgressCard =
      GlobalKey(debugLabel: 'tour.projectProgressCard');
  static final GlobalKey quickStatsRow =
      GlobalKey(debugLabel: 'tour.quickStatsRow');

  // ── Bottom nav (lives on every shell route) ─────────────────────────
  static final GlobalKey bottomNavHome =
      GlobalKey(debugLabel: 'tour.bottomNavHome');
  static final GlobalKey bottomNavProjects =
      GlobalKey(debugLabel: 'tour.bottomNavProjects');
  static final GlobalKey bottomNavFinancials =
      GlobalKey(debugLabel: 'tour.bottomNavFinancials');
  static final GlobalKey bottomNavExplore =
      GlobalKey(debugLabel: 'tour.bottomNavExplore');

  // ── Projects list ───────────────────────────────────────────────────
  static final GlobalKey projectsHeader =
      GlobalKey(debugLabel: 'tour.projectsHeader');
  static final GlobalKey projectsGrid =
      GlobalKey(debugLabel: 'tour.projectsGrid');

  // ── Financials ──────────────────────────────────────────────────────
  static final GlobalKey financialsHeader =
      GlobalKey(debugLabel: 'tour.financialsHeader');
  static final GlobalKey financialsTabs =
      GlobalKey(debugLabel: 'tour.financialsTabs');

  // ── Explore ─────────────────────────────────────────────────────────
  static final GlobalKey exploreFilters =
      GlobalKey(debugLabel: 'tour.exploreFilters');
  static final GlobalKey exploreGrid =
      GlobalKey(debugLabel: 'tour.exploreGrid');

  // ── Profile ─────────────────────────────────────────────────────────
  static final GlobalKey profileSecurityTile =
      GlobalKey(debugLabel: 'tour.profileSecurityTile');
  static final GlobalKey profileReplayTour =
      GlobalKey(debugLabel: 'tour.profileReplayTour');

  // ── Support ─────────────────────────────────────────────────────────
  static final GlobalKey supportWhatsappTech =
      GlobalKey(debugLabel: 'tour.supportWhatsappTech');
}
