import 'package:flutter_web_plugins/url_strategy.dart';

/// Web: use clean path-based URLs (e.g. /projects, /privacy-center) instead
/// of the default hash URLs (/#/projects). This makes deep links and shared
/// links real paths and lets a page refresh land on the same route.
///
/// REQUIRES a server-side SPA fallback so any path serves index.html — see
/// `web/_redirects` (`/*  /index.html  200`) for Netlify. Without it, a
/// refresh or shared deep link on a sub-path returns a 404.
void configureUrlStrategy() => usePathUrlStrategy();
