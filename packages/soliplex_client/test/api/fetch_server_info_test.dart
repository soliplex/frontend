import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

void main() {
  late MockHttpTransport mockTransport;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockTransport = MockHttpTransport();
  });

  tearDown(() {
    reset(mockTransport);
  });

  void stubResponse(Map<String, dynamic> body) {
    when(
      () => mockTransport.request<Map<String, dynamic>>(
        'GET',
        any(),
        body: any(named: 'body'),
        headers: any(named: 'headers'),
        timeout: any(named: 'timeout'),
        cancelToken: any(named: 'cancelToken'),
        fromJson: any(named: 'fromJson'),
      ),
    ).thenAnswer((_) async => body);
  }

  group('fetchServerInfo', () {
    test('returns parsed ServerInfo from backend response', () async {
      stubResponse(const {
        'installation_id': 'soliplex-conf-minimal',
        'name': 'Demo Server',
        'description': 'A friendly demo instance',
      });

      final info = await fetchServerInfo(
        transport: mockTransport,
        baseUrl: Uri.parse('https://api.example.com'),
      );

      expect(info, isNotNull);
      expect(info!.installationId, 'soliplex-conf-minimal');
      expect(info.name, 'Demo Server');
      expect(info.description, 'A friendly demo instance');
    });

    test('calls correct endpoint /api/v1/installation/identity', () async {
      stubResponse(const {'installation_id': 'id', 'name': 'X'});

      await fetchServerInfo(
        transport: mockTransport,
        baseUrl: Uri.parse('https://api.example.com'),
      );

      verify(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          Uri.parse('https://api.example.com/api/v1/installation/identity'),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
        ),
      ).called(1);
    });

    test('returns null when the server has no identity (404)', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
        ),
      ).thenThrow(const NotFoundException(message: 'Not found'));

      final info = await fetchServerInfo(
        transport: mockTransport,
        baseUrl: Uri.parse('https://api.example.com'),
      );

      expect(info, isNull);
    });

    test('propagates non-404 errors', () async {
      when(
        () => mockTransport.request<Map<String, dynamic>>(
          'GET',
          any(),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
        ),
      ).thenThrow(const NetworkException(message: 'Connection failed'));

      await expectLater(
        fetchServerInfo(
          transport: mockTransport,
          baseUrl: Uri.parse('https://api.example.com'),
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
