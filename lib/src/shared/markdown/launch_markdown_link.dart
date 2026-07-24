import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.markdown_link');

/// Opens a tapped markdown link in the platform's default handler — a browser
/// for `http(s):`, the mail client for `mailto:`, and so on.
///
/// Failures are logged rather than surfaced. A missing handler for a
/// non-web scheme (e.g. no mail client for `mailto:`) is a normal, expected
/// failure logged at warning level; a failure on an `http(s)` link is a dead
/// link — every target platform has a browser — so it is logged as an error.
/// Only the scheme is logged; the full href can carry an email address.
Future<void> launchMarkdownLink(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) {
    _logger.warning('Ignoring unparseable markdown link');
    return;
  }
  try {
    final launched = await launchUrl(uri);
    if (!launched) {
      _logLaunchFailure(uri, 'No handler available for link');
    }
  } on Exception catch (error, stackTrace) {
    _logLaunchFailure(uri, 'Failed to launch link', error, stackTrace);
  }
}

void _logLaunchFailure(
  Uri uri,
  String message, [
  Object? error,
  StackTrace? stackTrace,
]) {
  final detail = '$message (scheme: ${uri.scheme})';
  final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
  if (isWeb) {
    _logger.error(detail, error: error, stackTrace: stackTrace);
  } else {
    _logger.warning(detail, error: error, stackTrace: stackTrace);
  }
}
