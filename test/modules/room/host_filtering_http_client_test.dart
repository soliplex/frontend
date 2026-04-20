import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/access_policy.dart';
import 'package:soliplex_frontend/src/modules/room/host_filtering_http_client.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSoliplexHttpClient extends Mock implements SoliplexHttpClient {}

class _FakeHttpResponse extends Fake implements HttpResponse {}

class _FakeStreamedHttpResponse extends Fake implements StreamedHttpResponse {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _allowed = 'api.soliplex.ai';
const _denied = 'evil.com';

Uri _uri(String host) => Uri.parse('https://$host/path');

HostFilteringHttpClient _build({
  required SoliplexHttpClient inner,
  AccessPolicy policy = AccessPolicy.permissive,
}) =>
    HostFilteringHttpClient(inner: inner, policy: policy);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSoliplexHttpClient inner;

  setUpAll(() {
    registerFallbackValue(_FakeHttpResponse());
    registerFallbackValue(_FakeStreamedHttpResponse());
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    inner = MockSoliplexHttpClient();
  });

  group('HostFilteringHttpClient', () {
    group('permissive policy', () {
      test('request() forwards to inner for any host', () async {
        final fakeResponse = _FakeHttpResponse();
        when(() => inner.request(any(), any()))
            .thenAnswer((_) async => fakeResponse);

        final client = _build(inner: inner);
        final result = await client.request('GET', _uri('anywhere.com'));

        expect(result, same(fakeResponse));
        verify(() => inner.request('GET', _uri('anywhere.com'))).called(1);
      });

      test('requestStream() forwards to inner for any host', () async {
        final fakeResponse = _FakeStreamedHttpResponse();
        when(
          () => inner.requestStream(any(), any()),
        ).thenAnswer((_) async => fakeResponse);

        final client = _build(inner: inner);
        final result = await client.requestStream('GET', _uri('anywhere.com'));

        expect(result, same(fakeResponse));
      });
    });

    group('denyHosts', () {
      test('request() throws PolicyException for denied host', () async {
        final client = _build(
          inner: inner,
          policy: const AccessPolicy(denyHosts: {_denied}),
        );

        expect(
          () => client.request('GET', _uri(_denied)),
          throwsA(
            isA<PolicyException>().having(
              (e) => e.message,
              'message',
              contains(_denied),
            ),
          ),
        );
        verifyNever(() => inner.request(any(), any()));
      });

      test('requestStream() throws PolicyException for denied host', () async {
        final client = _build(
          inner: inner,
          policy: const AccessPolicy(denyHosts: {_denied}),
        );

        expect(
          () => client.requestStream('GET', _uri(_denied)),
          throwsA(isA<PolicyException>()),
        );
        verifyNever(() => inner.requestStream(any(), any()));
      });

      test('allows non-denied host', () async {
        final fakeResponse = _FakeHttpResponse();
        when(() => inner.request(any(), any()))
            .thenAnswer((_) async => fakeResponse);

        final client = _build(
          inner: inner,
          policy: const AccessPolicy(denyHosts: {_denied}),
        );
        final result = await client.request('GET', _uri(_allowed));

        expect(result, same(fakeResponse));
      });
    });

    group('allowHosts', () {
      test('request() throws for host not in allowlist', () {
        final client = _build(
          inner: inner,
          policy: const AccessPolicy(allowHosts: {_allowed}),
        );

        expect(
          () => client.request('GET', _uri(_denied)),
          throwsA(isA<PolicyException>()),
        );
      });

      test('request() forwards for host in allowlist', () async {
        final fakeResponse = _FakeHttpResponse();
        when(() => inner.request(any(), any()))
            .thenAnswer((_) async => fakeResponse);

        final client = _build(
          inner: inner,
          policy: const AccessPolicy(allowHosts: {_allowed}),
        );
        final result = await client.request('GET', _uri(_allowed));

        expect(result, same(fakeResponse));
      });
    });

    group('policy setter', () {
      test('updating policy takes effect immediately', () async {
        final fakeResponse = _FakeHttpResponse();
        when(() => inner.request(any(), any()))
            .thenAnswer((_) async => fakeResponse);

        final client = _build(inner: inner); // permissive

        // Initially allowed
        await client.request('GET', _uri(_denied));

        // Tighten
        client.policy = const AccessPolicy(denyHosts: {_denied});

        expect(
          () => client.request('GET', _uri(_denied)),
          throwsA(isA<PolicyException>()),
        );
      });
    });

    group('close', () {
      test('delegates close() to inner', () {
        when(() => inner.close()).thenReturn(null);
        final client = _build(inner: inner);
        client.close();
        verify(() => inner.close()).called(1);
      });
    });
  });
}
