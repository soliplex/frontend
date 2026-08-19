import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/status_message/status_message_fetcher.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeHttpClient client;
  late List<Uri> requested;

  setUp(() {
    requested = [];
    client = FakeHttpClient()
      ..onRequest = (method, uri) async {
        requested.add(uri);
        return HttpResponse(
          statusCode: 200,
          bodyBytes: Uint8List.fromList(
            utf8.encode(jsonEncode({'id': 'm', 'title': 't', 'body': 'b'})),
          ),
        );
      };
  });

  test('successive fetches request distinct URIs', () async {
    Future<void> fetch() => fetchStatusMessage(
          baseUrl: Uri.parse('https://example.test/'),
          client: client,
          path: '/messages/status.json',
        );

    await fetch();
    await fetch();

    expect(requested, hasLength(2));
    expect(requested[0], isNot(requested[1]));
  });

  test('cache busting preserves the path and its query parameters', () async {
    await fetchStatusMessage(
      baseUrl: Uri.parse('https://example.test/'),
      client: client,
      path: '/messages/status.json?tenant=acme&tenant=beta',
    );

    final uri = requested.single;
    expect(uri.path, '/messages/status.json');
    expect(uri.queryParametersAll['tenant'], ['acme', 'beta']);
  });
}
