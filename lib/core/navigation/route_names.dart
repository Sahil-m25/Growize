abstract final class RouteNames {
  static const String auth = '/auth';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String setupBiometric = '/setup-biometric';
  static const String setup = '/setup';
  static const String home = '/';
  static const String projects = '/projects';
  static const String financials = '/financials';
  static const String explore = '/explore';
  static const String gallery = '/gallery';
  static const String documents = '/documents';
  static const String activity = '/activity';
  static const String profile = '/profile';
  static const String support = '/support';
  static const String exit = '/exit';
  static const String kyc = '/kyc';
  static const String bankDetails = '/bank-details';
  static const String security = '/security';
  static const String privacyCenter = '/privacy-center';
  static const String biometric = '/biometric';
  static const String newTicket = '/new-ticket';
  static const String projectSelector = '/project-selector';
  static const String privacy = '/legal/privacy';
  static const String terms = '/legal/terms';
  // Routes with path params — use helper methods to build full paths
  static const String location = '/location';
  static const String ticketDetail = '/ticket';
  // Full-screen in-app document viewer. Sits outside the bottom-nav
  // shell so the PDF / image takes the full canvas. Path-param is the
  // `documents.id` UUID — deep-linkable but only resolves if the
  // current session can RLS-read the row.
  static const String documentViewer = '/document-viewer';

  static String locationPath(String projectId) => '/location/$projectId';
  static String projectDetailPath(String projectId) => '/projects/$projectId';
  static String ticketPath(String ticketId) => '/ticket/$ticketId';
  static String documentViewerPath(String documentId) =>
      '/document-viewer/$documentId';
}
