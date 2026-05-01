/// Centralized route paths.
///
/// Module registrations whose paths take parameters
/// (`/room/:serverAlias/:roomId`, etc.) keep their go_router-style
/// placeholder strings inline in the module file — those literal patterns
/// appear in exactly one place. Everything else lives here.
class AppRoutes {
  static const home = '/';
  static const lobby = '/lobby';
  static const servers = '/servers';
  static const versions = '/versions';
  static const networkInspector = '/diagnostics/network';
  static const authCallback = '/auth/callback';

  static String homeWithUrl(String url) => '/?url=${Uri.encodeComponent(url)}';

  static String versionsForServer(String serverAlias) =>
      '/versions/server/$serverAlias';

  static String room(String serverAlias, String roomId) =>
      '/room/$serverAlias/$roomId';

  static String roomInfo(String serverAlias, String roomId) =>
      '/room/$serverAlias/$roomId/info';

  static String thread(String serverAlias, String roomId, String threadId) =>
      '/room/$serverAlias/$roomId/thread/$threadId';

  static String quiz(
    String serverAlias,
    String roomId,
    String quizId, {
    String? from,
  }) {
    final base = '/room/$serverAlias/$roomId/quiz/$quizId';
    return from == null ? base : '$base?from=${Uri.encodeComponent(from)}';
  }
}
