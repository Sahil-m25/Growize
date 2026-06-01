/// Public-facing link constants used by the share flow.
///
/// `kPublicShareDomain` is the origin investors will copy/paste into
/// chats. Swap this when the production web app moves to a different
/// hostname (e.g. `https://invest.agresearchlabs.com`).
///
/// `publicProjectShareUrl` composes the canonical marketplace project
/// URL — kept here so every share surface (modal, deep-link card,
/// future email templates) builds the link the same way.
library;

/// Domain (no trailing slash) used when generating shareable links to
/// marketplace projects. Today the web build lives at growize.app; if
/// that ever changes we only update this constant.
const String kPublicShareDomain = 'https://growize.app';

/// Marketplace project deep-link — `<domain>/explore/<projectId>`.
/// The Explore detail route accepts this id and renders the project
/// without forcing a sign-in (see `router.dart`).
String publicProjectShareUrl(String projectId) =>
    '$kPublicShareDomain/explore/$projectId';
