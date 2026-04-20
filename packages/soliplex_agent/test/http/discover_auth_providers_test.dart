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

  group('discoverAuthProviders', () {
    test('returns parsed AuthProviderConfig list', () async {
      final responseBody = jsonEncode({
        'google': {
          'title': 'Google',
          'server_url': 'https://accounts.google.com',
          'client_id': 'client-123',
          'scope': 'openid profile',
        },
      });

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
          statusCode: 200,
          bodyBytes: Uint8List.fromList(utf8.encode(responseBody)),
          headers: const {'content-type': 'application/json'},
        ),
      );

      final providers = await discoverAuthProviders(
        serverUrl: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      expect(providers, hasLength(1));
      expect(providers.first.id, 'google');
      expect(providers.first.name, 'Google');
      expect(providers.first.serverUrl, 'https://accounts.google.com');
      expect(providers.first.clientId, 'client-123');
    });

    test('calls GET /api/login on the server URL', () async {
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
          statusCode: 200,
          bodyBytes: Uint8List.fromList(utf8.encode('{}')),
          headers: const {'content-type': 'application/json'},
        ),
      );

      await discoverAuthProviders(
        serverUrl: Uri.parse('https://api.example.com'),
        httpClient: mockClient,
      );

      final captured =
          verify(
            () => mockClient.request(
              'GET',
              captureAny(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
              timeout: any(named: 'timeout'),
            ),
          ).captured;
      expect(captured.single, Uri.parse('https://api.example.com/api/login'));
    });
  });
}
