import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show AuthException;

import 'package:soliplex_frontend/src/modules/room/ui/error_retry_panel.dart';

void main() {
  group('ErrorRetryPanel', () {
    testWidgets('auth error with onReauthenticate shows Sign in, not Retry',
        (tester) async {
      var signedIn = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorRetryPanel(
              title: 'Failed to load threads',
              error: const AuthException(message: 'no token', statusCode: 401),
              onRetry: () {},
              onReauthenticate: () => signedIn++,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      expect(signedIn, 1);
    });

    testWidgets('non-auth error shows Retry, not Sign in', (tester) async {
      var retried = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorRetryPanel(
              title: 'Failed to load messages',
              error: Exception('boom'),
              onRetry: () => retried++,
              onReauthenticate: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('auth error without onReauthenticate falls back to Retry',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorRetryPanel(
              title: 'Failed',
              error: const AuthException(message: 'no token', statusCode: 401),
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
