import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params_parser.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

MemorySink _captureLogs() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return sink;
}

/// The single warning `soliplex.auth_callback` recorded.
LogRecord _warning(MemorySink sink) => sink.records
    .where((r) =>
        r.loggerName == 'soliplex.auth_callback' && r.level == LogLevel.warning)
    .single;

void main() {
  group('parseCallbackParams', () {
    test('empty params returns NoCallbackParams', () {
      expect(parseCallbackParams({}), isA<NoCallbackParams>());
    });

    test('error param returns WebCallbackError', () {
      final result = parseCallbackParams({
        'error': 'access_denied',
        'error_description': 'User cancelled',
      });

      expect(result, isA<WebCallbackError>());
      final error = result as WebCallbackError;
      expect(error.error, 'access_denied');
      expect(error.errorDescription, 'User cancelled');
    });

    test('error without description sets description to null', () {
      final result = parseCallbackParams({'error': 'server_error'});

      final error = result as WebCallbackError;
      expect(error.error, 'server_error');
      expect(error.errorDescription, isNull);
    });

    test('token param returns WebCallbackSuccess', () {
      final result = parseCallbackParams({'token': 'abc123'});

      expect(result, isA<WebCallbackSuccess>());
      expect((result as WebCallbackSuccess).accessToken, 'abc123');
    });

    test('refresh_token and expires_in forwarded when present', () {
      final result = parseCallbackParams({
        'token': 'abc',
        'refresh_token': 'refresh-xyz',
        'expires_in': '3600',
      });

      final success = result as WebCallbackSuccess;
      expect(success.refreshToken, 'refresh-xyz');
      expect(success.expiresIn, 3600);
    });

    test('id_token forwarded when present', () {
      // Required for RP-Initiated Logout: Keycloak (and most OIDC IdPs)
      // need `id_token_hint` to deterministically end the SSO session.
      // Without it, the IdP falls back to a confirmation page whose
      // outcome is user-interactive — making logout intermittent.
      final result = parseCallbackParams({
        'token': 'abc',
        'id_token': 'idtok-xyz',
      });

      final success = result as WebCallbackSuccess;
      expect(success.idToken, 'idtok-xyz');
    });

    test('id_token absent leaves idToken null', () {
      final result = parseCallbackParams({'token': 'abc'});

      expect((result as WebCallbackSuccess).idToken, isNull);
    });

    test('invalid expires_in returns null', () {
      final result = parseCallbackParams({
        'token': 'abc',
        'expires_in': 'not-a-number',
      });

      expect((result as WebCallbackSuccess).expiresIn, isNull);
    });

    test('params without error or token returns NoCallbackParams', () {
      final result = parseCallbackParams({'state': 'some-state'});
      expect(result, isA<NoCallbackParams>());
    });
  });

  group('callbackQueryFromHash', () {
    test('returns the query of the sign-in callback route', () {
      expect(callbackQueryFromHash('#/auth/callback?token=abc&expires_in=60'),
          'token=abc&expires_in=60');
    });

    test('ignores other routes, even with a query', () {
      expect(callbackQueryFromHash('#/lobby?server=x'), isNull);
      expect(callbackQueryFromHash('#/?url=https%3A%2F%2Fa&returnTo=%2Fr'),
          isNull);
      expect(callbackQueryFromHash('#/auth/callback'), isNull);
      expect(callbackQueryFromHash(''), isNull);
    });
  });

  group('urlWithoutQueries', () {
    const page = 'https://soliplex.example/app/';

    String? clear(String hash,
            {String search = '', String pathname = '/app/'}) =>
        urlWithoutQueries(
          origin: 'https://soliplex.example',
          pathname: pathname,
          search: search,
          hash: hash,
        );

    test("drops a sign-in callback's tokens", () {
      expect(clear('#/auth/callback?token=x'), '$page#/auth/callback');
    });

    test("drops a lobby route's query", () {
      expect(clear('#/lobby?server=x'), '$page#/lobby');
    });

    test("drops the home route's query", () {
      expect(clear('#/?url=x'), '$page#/');
    });

    test('drops the query of a hash with no path', () {
      expect(clear('#?url=x'), '$page#');
    });

    test('drops the query of another spelling of the home route', () {
      expect(clear('#//?url=x'), '$page#//');
    });

    test('drops tokens in the address bar query', () {
      expect(clear('#/', search: '?token=a&refresh_token=b'), '$page#/');
    });

    test('drops the address bar query when there is no hash', () {
      expect(clear('', search: '?token=a'), page);
    });

    test('leaves a URL with no query unchanged', () {
      expect(clear('#/lobby'), isNull);
    });

    test('keeps the origin when the path reads as another host', () {
      expect(clear('#/auth/callback?token=abc', pathname: '//evil.example/'),
          startsWith('https://soliplex.example/'));
    });
  });

  group('captureCallback', () {
    test('reads the query index.html stashed', () {
      final captured = captureCallback(
        stashedQuery: 'token=abc&id_token=id',
        hash: '#/auth/callback',
      );

      expect(captured.scriptMissing, isFalse);
      final success = captured.params as WebCallbackSuccess;
      expect(success.accessToken, 'abc');
      expect(success.idToken, 'id');
    });

    test('falls back to the URL and flags the missing script', () {
      final captured = captureCallback(
        stashedQuery: null,
        hash: '#/auth/callback?token=abc',
      );

      expect(captured.scriptMissing, isTrue);
      expect((captured.params as WebCallbackSuccess).accessToken, 'abc');
    });

    test('an ordinary page load is no callback and no missing script', () {
      final captured =
          captureCallback(stashedQuery: null, hash: '#/lobby?server=x');

      expect(captured.params, isA<NoCallbackParams>());
      expect(captured.scriptMissing, isFalse);
    });

    test('ignores an access_token key', () {
      final captured = captureCallback(
        stashedQuery: 'access_token=abc',
        hash: '#/auth/callback',
      );

      expect(captured.params, isA<NoCallbackParams>());
    });

    test('an illegal percent encoding in the stash is malformed', () {
      final sink = _captureLogs();

      final captured = captureCallback(
        stashedQuery: 'token=secret%ZZ',
        hash: '#/auth/callback',
      );

      expect(captured.params, isA<WebCallbackMalformed>());
      expect(captured.scriptMissing, isFalse);
      final record = _warning(sink);
      expect(record.attributes, {'failure': 'ArgumentError'});
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
      expect(record.toString(), isNot(contains('secret')));
    });

    test('invalid UTF-8 in the URL is malformed and still flags the script',
        () {
      final sink = _captureLogs();

      final captured = captureCallback(
        stashedQuery: null,
        hash: '#/auth/callback?token=secret%E0%A4',
      );

      expect(captured.params, isA<WebCallbackMalformed>());
      expect(captured.scriptMissing, isTrue);
      final record = _warning(sink);
      expect(record.attributes['failure'], startsWith('FormatException'));
      expect(record.error, isNull);
      expect(record.toString(), isNot(contains('secret')));
      expect(record.attributes.toString(), isNot(contains('secret')));
    });
  });
}
