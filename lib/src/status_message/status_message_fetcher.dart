import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'status_message.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.status_message');

typedef StatusMessageFetcher = Future<StatusMessage?> Function();

Future<StatusMessage?> fetchStatusMessage({
  required Uri baseUrl,
  required SoliplexHttpClient client,
  required String path,
}) async {
  final transport = HttpTransport(client: client);
  final uri = baseUrl.resolve(path);
  try {
    final json = await transport.request<Map<String, dynamic>>('GET', uri);
    final message = StatusMessage.fromJson(json);
    final window = message.window;
    if (json['window'] != null && window == null) {
      // Operator authored a window we couldn't use (not an object, unparseable,
      // or a non-UTC bound). Surface it; the message still shows windowless.
      _logger.warning('Status message has a malformed window at $uri; '
          'showing the message without it.');
    } else if (window != null && !window.isValid) {
      // Operator-authored `end` precedes `start`. Surface the mistake (the
      // banner flags the range in error colour) rather than dropping the
      // message.
      _logger.warning('Status message window end precedes start at $uri');
    }
    return message;
  } on NotFoundException {
    return null; // No file configured — the steady state.
  } on NetworkException catch (e) {
    // Offline, timeout, a connection refused mid-flight — the expected
    // transient noise for an auxiliary banner. Log quietly and degrade to
    // "no message"; the next poll recovers.
    _logger.debug('Status message fetch failed for $uri', error: e);
    return null;
  } on FormatException catch (e) {
    _logger.warning('Malformed status message at $uri', error: e);
    return null;
  } on Object catch (e) {
    // A persistent misconfiguration — an auth wall, a permission error, a 5xx,
    // a wrong content type, or HTML served in place of the JSON. Surface it so
    // an operator can tell "no message posted" from "message posted but
    // broken"; still degrade to "no message" for the user.
    _logger.warning('Status message fetch failed for $uri', error: e);
    return null;
  }
}

StatusMessageFetcher serverStatusMessageFetcher({
  required Uri baseUrl,
  required SoliplexHttpClient client,
  required String path,
}) =>
    () => fetchStatusMessage(baseUrl: baseUrl, client: client, path: path);
