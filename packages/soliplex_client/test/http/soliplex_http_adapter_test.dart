import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:test/test.dart';

class MockSoliplexHttpClient extends Mock implements SoliplexHttpClient {}

void main() {
  late MockSoliplexHttpClient mockClient;
  late SoliplexHttpAdapter adapter;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockClient = MockSoliplexHttpClient();
    adapter = SoliplexHttpAdapter(mockClient);
  });

  tearDown(() {
    reset(mockClient);
  });

  StreamedHttpResponse streamResponse() {
    return const StreamedHttpResponse(statusCode: 200, body: Stream.empty());
  }

  group('SoliplexHttpAdapter', () {
    test('sends empty body as null', () async {
      when(
        () => mockClient.requestStream(
          any(),
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => streamResponse());

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      await adapter.send(request);

      final captured =
          verify(
            () => mockClient.requestStream(
              'GET',
              Uri.parse('https://example.com/api'),
              headers: any(named: 'headers'),
              body: captureAny(named: 'body'),
            ),
          ).captured;

      expect(captured.single, isNull);
    });

    test('sends non-empty body as bytes', () async {
      when(
        () => mockClient.requestStream(
          any(),
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => streamResponse());

      final request = http.Request('POST', Uri.parse('https://example.com/api'))
        ..body = '{"key":"value"}';
      await adapter.send(request);

      final captured =
          verify(
            () => mockClient.requestStream(
              'POST',
              Uri.parse('https://example.com/api'),
              headers: any(named: 'headers'),
              body: captureAny(named: 'body'),
            ),
          ).captured;

      expect(captured.single, isNotNull);
      expect(captured.single, isA<List<int>>());
    });
  });
}
