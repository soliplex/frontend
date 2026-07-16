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
    return StatusMessage.fromJson(json);
  } on NotFoundException {
    return null; // No file configured — the steady state.
  } on FormatException catch (e) {
    _logger.warning('Malformed status message at $uri', error: e);
    return null;
  } on Object catch (e) {
    _logger.debug('Status message fetch failed for $uri', error: e);
    return null;
  }
}

StatusMessageFetcher serverStatusMessageFetcher({
  required Uri baseUrl,
  required SoliplexHttpClient client,
  required String path,
}) =>
    () => fetchStatusMessage(baseUrl: baseUrl, client: client, path: path);
