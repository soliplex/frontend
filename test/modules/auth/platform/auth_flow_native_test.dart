@TestOn('vm')
library;

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow_native.dart';

class _ThrowingAppAuth implements FlutterAppAuth {
  _ThrowingAppAuth(this._error);

  final Object _error;

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) async {
    throw _error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_ThrowingAppAuth.${invocation.memberName}');
}

void main() {
  group('NativeAuthFlow.endSession', () {
    test('rethrows when the underlying _appAuth.endSession throws', () async {
      final sentinel = Exception('idp unreachable');
      final flow = createAuthFlow(
        redirectScheme: 'ai.soliplex.client',
        appAuth: _ThrowingAppAuth(sentinel),
      );

      expect(
        () => flow.endSession(
          discoveryUrl:
              'https://idp.example.com/.well-known/openid-configuration',
          endSessionEndpoint: 'https://idp.example.com/logout',
          idToken: 'id-token',
          clientId: 'client-id',
        ),
        throwsA(same(sentinel)),
      );
    });
  });
}
