import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/server_sign_out_control.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../helpers/fakes.dart';

/// What [NativeAuthFlow.endSession] throws for a failed sign-out.
const _nativeFailure = AuthException(
  'Sign-out with the identity provider failed',
  kind: AuthFailureKind.unknown,
);

ServerManager _manager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void _signIn(ServerEntry entry) => entry.auth.login(
      provider: const OidcProvider(
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        clientId: 'soliplex',
      ),
      tokens: AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        idToken: 'id-1',
      ),
    );

Future<void> _tapSignOut(WidgetTester tester) async {
  await tester.tap(find.text('Sign out'));
  await tester.pumpAndSettle();
}

Future<void> _tapRemove(WidgetTester tester,
    {String confirm = 'Remove'}) async {
  await tester.tap(find.text('Remove'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(SoliplexButton, confirm));
  await tester.pumpAndSettle();
}

/// Starts the action under test: a removal (confirmed) or a sign-out.
Future<void> _start(WidgetTester tester, {required bool remove}) =>
    remove ? _tapRemove(tester) : _tapSignOut(tester);

Future<void> _chooseFromErrorMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byIcon(Icons.error_outline));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

MemorySink _captureLogs() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return sink;
}

void main() {
  // Built inside each test body, so the manager's storage writes run in the
  // test's fake-async zone rather than one it never drives.
  late ServerManager manager;
  late ServerEntry entry;
  late FakeAuthFlow flow;

  void createServer() {
    manager = _manager();
    entry = manager.addServer(
      serverId: 'srv',
      serverUrl: Uri.parse('https://api.example.com'),
    );
    flow = FakeAuthFlow();
  }

  Future<void> pumpControl(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            authFlowProvider.overrideWithValue(flow),
            probeClientProvider.overrideWithValue(FakeHttpClient()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ServerSignOutControl(
                entry: entry,
                serverManager: manager,
                idleBuilder: (context, {required signOut, required remove}) =>
                    Row(
                  children: [
                    TextButton(
                        onPressed: signOut, child: const Text('Sign out')),
                    TextButton(onPressed: remove, child: const Text('Remove')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  /// A signed-in server whose sign-out fails as a native one does.
  Future<void> pumpFailingControl(WidgetTester tester) {
    createServer();
    _signIn(entry);
    flow.endSessionError = _nativeFailure;
    return pumpControl(tester);
  }

  testWidgets('signOut ends the IdP session and keeps the server',
      (tester) async {
    createServer();
    _signIn(entry);
    await pumpControl(tester);

    await _tapSignOut(tester);

    expect(flow.endSessionCalled, isTrue);
    expect(entry.auth.session.value, isA<NoSession>());
    expect(manager.servers.value, contains('srv'));
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('remove confirms, ends the IdP session and removes the server',
      (tester) async {
    createServer();
    _signIn(entry);
    await pumpControl(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove server?'), findsOneWidget);
    expect(find.textContaining("You'll be signed out of"), findsOneWidget);
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(flow.endSessionCalled, isTrue);
    expect(manager.servers.value, isNot(contains('srv')));
  });

  testWidgets('remove without a session removes outright', (tester) async {
    createServer();
    await pumpControl(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.textContaining("You'll be signed out"), findsNothing);
    expect(find.textContaining("Remove 'https://api.example.com'?"),
        findsOneWidget);
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(flow.endSessionCalled, isFalse);
    expect(manager.servers.value, isNot(contains('srv')));
  });

  testWidgets('cancelling the confirmation leaves everything untouched',
      (tester) async {
    createServer();
    _signIn(entry);
    await pumpControl(tester);

    await _tapRemove(tester, confirm: 'Cancel');

    expect(flow.endSessionCalled, isFalse);
    expect(entry.auth.isAuthenticated, isTrue);
    expect(manager.servers.value, contains('srv'));
    expect(find.text('Sign out'), findsOneWidget);
  });

  for (final (:remove, :title) in [
    (remove: false, title: 'Log out failed'),
    (remove: true, title: 'Server kept — sign-out failed'),
  ]) {
    testWidgets(
        'a failed ${remove ? 'removal' : 'sign-out'} keeps the server and '
        'shows the error', (tester) async {
      await pumpFailingControl(tester);

      await _start(tester, remove: remove);

      expect(entry.auth.isAuthenticated, isTrue);
      expect(manager.servers.value, contains('srv'));
      expect(find.text('Sign out'), findsNothing);

      await _chooseFromErrorMenu(tester, 'Show error detail');
      expect(find.text(title), findsOneWidget);
      expect(
        find.text('Sign-out failed. Please try again.'),
        findsOneWidget,
      );

      // Closing the dialog leaves the error in place.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
        'Try again repeats the failed ${remove ? 'removal' : 'sign-out'}',
        (tester) async {
      await pumpFailingControl(tester);
      await _start(tester, remove: remove);

      flow
        ..endSessionError = null
        ..endSessionCalled = false;
      await _chooseFromErrorMenu(tester, 'Try again');

      expect(flow.endSessionCalled, isTrue);
      expect(entry.auth.session.value, isA<NoSession>());
      expect(manager.servers.value.containsKey('srv'), !remove);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  }

  testWidgets('Remove server after a failed sign-out removes outright',
      (tester) async {
    await pumpFailingControl(tester);
    await _tapSignOut(tester);

    flow.endSessionCalled = false;
    await _chooseFromErrorMenu(tester, 'Remove server');

    expect(flow.endSessionCalled, isFalse);
    expect(manager.servers.value, isNot(contains('srv')));
  });

  testWidgets('a sign-out that fails after the session changed shows the error',
      (tester) async {
    final pending = Completer<void>();
    await pumpFailingControl(tester);
    flow.endSessionCompleter = pending;

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    // Stands in for a token refresh while the IdP sheet is open: both install
    // a new ActiveSession.
    _signIn(entry);
    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a failure stops showing once the session changes',
      (tester) async {
    await pumpFailingControl(tester);
    await _tapSignOut(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    entry.auth.markSessionExpired();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });

  for (final (:remove, :message) in [
    (remove: false, message: 'Sign-out failed'),
    (remove: true, message: 'Sign-out failed; server kept'),
  ]) {
    testWidgets(
        'a failed ${remove ? 'removal' : 'sign-out'} logs one warning with '
        'the server id', (tester) async {
      final sink = _captureLogs();
      await pumpFailingControl(tester);

      await _start(tester, remove: remove);

      final warnings =
          sink.records.where((r) => r.level == LogLevel.warning).toList();
      expect(warnings, hasLength(1));
      final record = warnings.single;
      expect(record.message, message);
      expect(record.attributes, {'serverId': 'srv'});
      expect(record.stackTrace, isNotNull);
    });
  }

  testWidgets('the spinner is labelled while signing out', (tester) async {
    createServer();
    _signIn(entry);
    flow.endSessionCompleter = Completer<void>();
    await pumpControl(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(find.byTooltip('Signing out'), findsOneWidget);
  });
}
