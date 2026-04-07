import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart' hide CancelToken;
// ignore: implementation_imports
import 'package:ag_ui/src/sse/sse_parser.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';

/// Streams AG-UI events using the Soliplex HTTP stack directly.
///
/// Replaces [AgUiClient] usage in pure Dart packages. Routes SSE through
/// [HttpTransport] so status code mapping, auth, observability, cancel
/// wrapping, and platform clients apply automatically. No retry, no
/// reconnection, no duplicate CancelToken.
class AgUiStreamClient {
  /// Creates a client that streams AG-UI events via [httpTransport].
  AgUiStreamClient({
    required HttpTransport httpTransport,
    required UrlBuilder urlBuilder,
  })  : _httpTransport = httpTransport,
        _urlBuilder = urlBuilder;

  final HttpTransport _httpTransport;
  final UrlBuilder _urlBuilder;

  /// Streams AG-UI events for a run.
  ///
  /// Posts [input] to [endpoint] and parses the SSE response into
  /// typed [BaseEvent]s. The endpoint is relative to the base URL
  /// (e.g. `'rooms/my-room/agui/thread-1/run-1'`).
  Stream<BaseEvent> runAgent(
    String endpoint,
    SimpleRunAgentInput input, {
    CancelToken? cancelToken,
  }) async* {
    final response = await _httpTransport.requestStream(
      'POST',
      _urlBuilder.build(path: endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      },
      body: input.toJson(),
      cancelToken: cancelToken,
    );

    final sseMessages = SseParser().parseBytes(response.body);
    const decoder = EventDecoder();

    await for (final message in sseMessages) {
      if (message.data == null || message.data!.isEmpty) continue;
      try {
        final jsonData = json.decode(message.data!);
        if (jsonData is Map<String, dynamic>) {
          yield decoder.decodeJson(jsonData);
        } else if (jsonData is List) {
          for (final item in jsonData) {
            if (item is Map<String, dynamic>) {
              try {
                yield decoder.decodeJson(item);
              } on DecodingError catch (e) {
                developer.log(
                  'Skipped undecodable AG-UI event in batch: $e',
                  name: 'soliplex_client.agui_stream',
                  level: 900,
                );
              }
            } else {
              developer.log(
                'Skipped non-object item in AG-UI batch: '
                '${item.runtimeType}',
                name: 'soliplex_client.agui_stream',
                level: 900,
              );
            }
          }
        }
      } on FormatException catch (e) {
        developer.log(
          'Skipped malformed JSON in SSE event: $e',
          name: 'soliplex_client.agui_stream',
          level: 900,
        );
      } on DecodingError catch (e) {
        developer.log(
          'Skipped undecodable AG-UI event: $e',
          name: 'soliplex_client.agui_stream',
          level: 900,
        );
      }
    }
  }

  /// Closes the underlying transport.
  void close() => _httpTransport.close();
}
