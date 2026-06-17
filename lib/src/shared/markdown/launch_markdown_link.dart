import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.markdown_link');

/// Opens a tapped markdown link in the platform's default handler — a browser
/// for `http(s):`, the mail client for `mailto:`, and so on.
///
/// A missing handler (e.g. no mail client installed) is a normal failure, not
/// an error, so it is logged rather than surfaced. Only the scheme is logged;
/// the full href can carry an email address.
Future<void> launchMarkdownLink(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) {
    _logger.warning('Ignoring unparseable markdown link');
    return;
  }
  try {
    final launched = await launchUrl(uri);
    if (!launched) {
      _logger.warning('No handler available for link (scheme: ${uri.scheme})');
    }
  } on Exception catch (error, stackTrace) {
    _logger.warning(
      'Failed to launch link (scheme: ${uri.scheme})',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
