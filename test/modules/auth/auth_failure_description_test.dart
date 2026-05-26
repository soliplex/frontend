import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_failure_description.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';

void main() {
  group('describeAuthFailure', () {
    test('cancelled returns neutral copy', () {
      expect(
        describeAuthFailure(kind: AuthFailureKind.cancelled),
        'Sign-in was cancelled.',
      );
    });

    test('discoveryUnreachable includes server URL when provided', () {
      expect(
        describeAuthFailure(
          kind: AuthFailureKind.discoveryUnreachable,
          serverUrl: 'https://rag.example.net',
        ),
        contains('https://rag.example.net'),
      );
      expect(
        describeAuthFailure(kind: AuthFailureKind.discoveryUnreachable),
        contains('sign-in server'),
      );
    });

    test('network is actionable', () {
      expect(
        describeAuthFailure(kind: AuthFailureKind.network),
        contains('connection'),
      );
    });

    test('idpRejected access_denied has a friendly message', () {
      expect(
        describeAuthFailure(
          kind: AuthFailureKind.idpRejected,
          oauthError: 'access_denied',
        ),
        'The identity provider rejected the sign-in request.',
      );
    });

    test('idpRejected invalid_grant maps to re-login copy', () {
      expect(
        describeAuthFailure(
          kind: AuthFailureKind.idpRejected,
          oauthError: 'invalid_grant',
        ),
        contains('expired'),
      );
    });

    test('idpRejected unknown oauthError falls back gracefully', () {
      expect(
        describeAuthFailure(
          kind: AuthFailureKind.idpRejected,
          oauthError: 'some_future_code',
        ),
        'Sign-in was rejected. Please try again.',
      );
      expect(
        describeAuthFailure(
          kind: AuthFailureKind.idpRejected,
          oauthError: 'some_future_code',
        ),
        isNot(contains('some_future_code')),
      );
    });

    test('noBrowser tells user to install a browser', () {
      expect(
        describeAuthFailure(kind: AuthFailureKind.noBrowser),
        contains('browser'),
      );
    });

    test('unknown falls back to a clean retry message', () {
      expect(
        describeAuthFailure(kind: AuthFailureKind.unknown),
        'Sign-in failed. Please try again.',
      );
    });

    test(
        'output never contains the literal word "Exception" or runtimeType junk',
        () {
      for (final kind in AuthFailureKind.values) {
        final copy = describeAuthFailure(kind: kind);
        expect(copy, isNot(contains('Exception')));
        expect(copy, isNot(contains('runtimeType')));
        expect(copy, isNot(matches(RegExp(r'\(\w{3,4}\)\.'))),
            reason: 'Avoid leaking minified type names like "(Nra).": $copy');
      }
    });
  });
}
