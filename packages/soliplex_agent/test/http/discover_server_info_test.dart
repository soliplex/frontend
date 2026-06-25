import 'dart:convert';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements SoliplexHttpClient {}

void main() {
  late _MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockClient = _MockHttpClient();
  });

  void stub({required int statusCode, required String body}) {
    when(
      () => mockClient.request(
        any(),
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer(
      (_) async => HttpResponse(
        statusCode: statusCode,
        bodyBytes: Uint8List.fromList(utf8.encode(body)),
        headers: const {'content-type': 'application/json'},
      ),
    );
  }

  group('discoverServerInfo', () {
    test('returns parsed ServerInfo', () async {
      stub(
        statusCode: 200,
        body: jsonEncode({
          'installation_id': 'soliplex-conf-minimal',
          'name': 'Demo Server',
          'description': 'A friendly demo instance',
        }),
      );

      final info = await discoverServerInfo(
        serverUrl: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      expect(info, isNotNull);
      expect(info!.name, 'Demo Server');
      expect(info.description, 'A friendly demo instance');
    });

    test('returns null on 404', () async {
      stub(statusCode: 404, body: '{"detail":"server info not configured"}');

      final info = await discoverServerInfo(
        serverUrl: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      expect(info, isNull);
    });

    test('calls GET /api/v1/installation/identity on the server URL', () async {
      stub(
        statusCode: 200,
        body: jsonEncode({'installation_id': 'id', 'name': 'X'}),
      );

      await discoverServerInfo(
        serverUrl: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      final captured = verify(
        () => mockClient.request(
          'GET',
          captureAny(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
          timeout: any(named: 'timeout'),
        ),
      ).captured;
      expect(
        captured.single,
        Uri.parse('https://api.example.com/api/v1/installation/identity'),
      );
    });
  });
}
