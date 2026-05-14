abstract final class RouteNames {
  static const String auth = '/auth';
  static const String login = '/login';
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
  static const String biometric = '/biometric';
  static const String newTicket = '/new-ticket';
  static const String projectSelector = '/project-selector';
  static const String privacy = '/legal/privacy';
  static const String terms = '/legal/terms';
  // Routes with path params — use helper methods to build full paths
  static const String location = '/location';
  static const String ticketDetail = '/ticket';

  static String locationPath(String projectId) => '/location/$projectId';
  static String projectDetailPath(String projectId) => '/projects/$projectId';
  static String ticketPath(String ticketId) => '/ticket/$ticketId';
}
