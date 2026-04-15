import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthenticatedHttpClient,
        RefreshingHttpClient,
        RetryingHttpClient;
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements SoliplexHttpClient {}

class _MockObserver extends Mock implements HttpObserver {}

class _MockTokenRefresher extends Mock implements TokenRefresher {}

void main() {
  group('createAgentHttpClient', () {
    test('no args wraps DartHttpClient with RetryingHttpClient', () {
      final client = createAgentHttpClient();
      addTearDown(client.close);
      expect(client, isA<RetryingHttpClient>());
    });

    test('with innerClient wraps in RetryingHttpClient', () {
      final inner = _MockHttpClient();
      final client = createAgentHttpClient(innerClient: inner);
      addTearDown(client.close);
      expect(client, isA<RetryingHttpClient>());
    });

    test('with observers wraps Observable then Retrying', () {
      final observer = _MockObserver();
      final client = createAgentHttpClient(observers: [observer]);
      addTearDown(client.close);
      expect(client, isA<RetryingHttpClient>());
    });

    test('with empty observers wraps in RetryingHttpClient only', () {
      final client = createAgentHttpClient(observers: <HttpObserver>[]);
      addTearDown(client.close);
      expect(client, isA<RetryingHttpClient>());
    });

    test('with innerClient and observers wraps both', () {
      final inner = _MockHttpClient();
      final observer = _MockObserver();
      final client = createAgentHttpClient(
        innerClient: inner,
        observers: [observer],
      );
      addTearDown(client.close);
      expect(client, isA<RetryingHttpClient>());
    });

    test('close cascades through decorator stack', () {
      final inner = _MockHttpClient();
      createAgentHttpClient(
        innerClient: inner,
        observers: [_MockObserver()],
      ).close();
      verify(inner.close).called(1);
    });

    group('auth', () {
      test('with getToken wraps in AuthenticatedHttpClient', () {
        final client = createAgentHttpClient(getToken: () => 'token');
        addTearDown(client.close);
        expect(client, isA<AuthenticatedHttpClient>());
      });

      test('with getToken and observers applies both layers', () {
        final client = createAgentHttpClient(
          getToken: () => 'token',
          observers: [_MockObserver()],
        );
        addTearDown(client.close);
        // Outermost is AuthenticatedHttpClient
        expect(client, isA<AuthenticatedHttpClient>());
      });

      test('with tokenRefresher wraps in RefreshingHttpClient', () {
        final client = createAgentHttpClient(
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        );
        addTearDown(client.close);
        expect(client, isA<RefreshingHttpClient>());
      });

      test('with all parameters composes full decorator stack', () {
        final client = createAgentHttpClient(
          observers: [_MockObserver()],
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        );
        addTearDown(client.close);
        // Outermost is RefreshingHttpClient
        expect(client, isA<RefreshingHttpClient>());
      });

      test('tokenRefresher without getToken throws assertion', () {
        expect(
          () => createAgentHttpClient(tokenRefresher: _MockTokenRefresher()),
          throwsA(isA<AssertionError>()),
        );
      });

      test('close cascades through full auth stack', () {
        final inner = _MockHttpClient();
        createAgentHttpClient(
          innerClient: inner,
          observers: [_MockObserver()],
          getToken: () => 'token',
          tokenRefresher: _MockTokenRefresher(),
        ).close();
        verify(inner.close).called(1);
      });
    });
  });
}
