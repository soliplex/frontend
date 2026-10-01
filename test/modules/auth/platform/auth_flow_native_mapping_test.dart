import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow_native.dart';

class _MockAppAuth extends Mock implements FlutterAppAuth {}

void main() {
  late _MockAppAuth appAuth;
  late NativeAuthFlow flow;
  const provider = AuthProviderConfig(
    id: 'idp',
    name: 'IdP',
    serverUrl: 'https://idp.example.com',
    clientId: 'cid',
    scope: 'openid profile',
  );

  setUpAll(() {
    registerFallbackValue(
      AuthorizationTokenRequest(
        'id',
        'app://callback',
        discoveryUrl: 'https://example.com/.well-known/openid-configuration',
      ),
    );
    registerFallbackValue(EndSessionRequest());
  });

  setUp(() {
    appAuth = _MockAppAuth();
    flow = NativeAuthFlow(appAuth: appAuth, redirectScheme: 'app');
  });

  Future<AuthException> capture() async {
    try {
      await flow.authenticate(provider);
      fail('expected throw');
    } on AuthException catch (e) {
      return e;
    }
  }

  AuthorizationTokenResponse validResponse() => AuthorizationTokenResponse(
        'access',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );

  group('NativeAuthFlow exception mapping', () {
    test('FlutterAppAuthUserCancelledException → cancelled', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthUserCancelledException(
          code: 'user_cancelled',
          message: 'cancelled',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.cancelled);
    });

    test('FlutterAppAuthPlatformException no_browser_available → noBrowser',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'no_browser_available',
          message: 'no browser',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.noBrowser);
    });

    test(
        'FlutterAppAuthPlatformException discovery_failed → discoveryUnreachable',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'discovery_failed',
          message: 'failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.discoveryUnreachable);
    });

    test(
        'authorize_and_exchange_code_failed + discovery domain → discoveryUnreachable',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'authorize_and_exchange_code_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            domain: 'org.openid.appauth.discovery',
            code: '0',
          ),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.discoveryUnreachable);
    });

    test('authorize_and_exchange_code_failed + NSURLErrorDomain → network',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'authorize_and_exchange_code_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            domain: 'NSURLErrorDomain',
            code: '-1009',
          ),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.network);
    });

    test('authorize_failed + OAuth error → idpRejected with oauthError',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'authorize_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: 'access_denied',
            errorDescription: 'user denied',
          ),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.idpRejected);
      expect(e.oauthError, 'access_denied');
    });

    test('token_failed + OAuth error → idpRejected with oauthError', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: 'invalid_grant',
          ),
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.idpRejected);
      expect(e.oauthError, 'invalid_grant');
    });

    test('PlatformException (channel error) → unknown', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        PlatformException(code: 'channel_error'),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.unknown);
    });

    test('FormatException → unknown', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        const FormatException('unexpected'),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.unknown);
    });

    test('message does not contain runtimeType pattern', () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenThrow(
        const FormatException('boom'),
      );
      final e = await capture();
      expect(e.message, isNot(contains('runtimeType')));
      expect(e.message, isNot(matches(RegExp(r'\(\w{3,4}\)\.'))));
    });

    test('null access token → unknown with "no access token" in message',
        () async {
      when(() => appAuth.authorizeAndExchangeCode(any())).thenAnswer(
        (_) async => AuthorizationTokenResponse(
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
        ),
      );
      final e = await capture();
      expect(e.kind, AuthFailureKind.unknown);
      expect(e.message, contains('no access token'));
    });
  });

  group('NativeAuthFlow forceLoginPrompt', () {
    test('omits prompt=login when forceLoginPrompt is false', () async {
      when(() => appAuth.authorizeAndExchangeCode(any()))
          .thenAnswer((_) async => validResponse());

      await flow.authenticate(provider);

      final captured = verify(
        () => appAuth.authorizeAndExchangeCode(captureAny()),
      ).captured.single as AuthorizationTokenRequest;
      expect(captured.additionalParameters, isNull);
    });

    test('passes prompt=login when forceLoginPrompt is true', () async {
      when(() => appAuth.authorizeAndExchangeCode(any()))
          .thenAnswer((_) async => validResponse());

      await flow.authenticate(provider, forceLoginPrompt: true);

      final captured = verify(
        () => appAuth.authorizeAndExchangeCode(captureAny()),
      ).captured.single as AuthorizationTokenRequest;
      expect(captured.additionalParameters, equals({'prompt': 'login'}));
    });
  });

  group('NativeAuthFlow scopes', () {
    Future<AuthorizationTokenRequest> authenticateWith(
      AuthProviderConfig config,
    ) async {
      when(() => appAuth.authorizeAndExchangeCode(any()))
          .thenAnswer((_) async => validResponse());

      await flow.authenticate(config);

      return verify(
        () => appAuth.authorizeAndExchangeCode(captureAny()),
      ).captured.single as AuthorizationTokenRequest;
    }

    test('requests the configured scopes', () async {
      final captured = await authenticateWith(provider);

      expect(captured.scopes, ['openid', 'profile']);
    });

    test('requests no scopes when the provider configures none', () async {
      final captured = await authenticateWith(
        const AuthProviderConfig(
          id: 'idp',
          name: 'IdP',
          serverUrl: 'https://idp.example.com',
          clientId: 'cid',
          scope: null,
        ),
      );

      expect(captured.scopes, isNull);
    });
  });

  group('NativeAuthFlow endSession failure', () {
    const token = 'eyJhbGciOiJSUzI1NiJ9.secret-id-token';
    const leakyText = 'State mismatch for '
        'https://idp.example.com/logout?id_token_hint=$token';
    final leakyDetails = FlutterAppAuthPlatformErrorDetails(
      errorDescription: leakyText,
      errorDebugDescription: leakyText,
      rootCauseDebugDescription: leakyText,
    );

    // A known origin, so the test can tell the plugin's frames were kept.
    final origin = StackTrace.fromString('#0 appAuthEndSession (plugin.dart)');

    Future<(AuthException, StackTrace)> captureEndSession(
      PlatformException failure,
    ) async {
      when(() => appAuth.endSession(any()))
          .thenAnswer((_) => Future.error(failure, origin));
      try {
        await flow.endSession(
          discoveryUrl:
              'https://idp.example.com/.well-known/openid-configuration',
          endSessionEndpoint: null,
          idToken: token,
          clientId: 'cid',
        );
        fail('expected throw');
      } on AuthException catch (e, st) {
        return (e, st);
      }
    }

    test('a failure becomes an unknown AuthException with fixed text',
        () async {
      final (e, st) = await captureEndSession(
        FlutterAppAuthPlatformException(
          code: 'end_session_failed',
          message: leakyText,
          legacyDetails: {'error_debug_description': leakyText},
          platformErrorDetails: leakyDetails,
        ),
      );

      expect(e.kind, AuthFailureKind.unknown);
      expect(e.toString(), isNot(contains(token)));
      expect(st.toString(), origin.toString());
    });

    test('a cancellation becomes a cancelled AuthException with fixed text',
        () async {
      final (e, st) = await captureEndSession(
        FlutterAppAuthUserCancelledException(
          code: 'end_session_failed',
          message: leakyText,
          legacyDetails: {'error_debug_description': leakyText},
          platformErrorDetails: leakyDetails,
        ),
      );

      expect(e.kind, AuthFailureKind.cancelled);
      expect(e.toString(), isNot(contains(token)));
      expect(st.toString(), origin.toString());
    });
  });
}
