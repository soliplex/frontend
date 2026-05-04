import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show BackendVersionInfo;
import 'package:soliplex_frontend/src/modules/versions/versions_screen.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

ServerManager _serverManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildApp(Widget child) => MaterialApp(home: child);

void main() {
  group('VersionsScreen', () {
    testWidgets('shows app and framework rows in Frontend section',
        (tester) async {
      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: _serverManager(),
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (_) async =>
            throw UnimplementedError('no servers in this test'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Frontend'), findsOneWidget);
      expect(find.text('App'), findsOneWidget);
      expect(find.text('Acme 0.0.46+48'), findsOneWidget);
      expect(find.text('Framework'), findsOneWidget);
      expect(find.textContaining('soliplex_frontend '), findsOneWidget);
    });

    testWidgets('shows empty-servers state when no servers connected',
        (tester) async {
      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Soliplex',
        serverManager: _serverManager(),
        versionLoader: () async => '1.0.0+1',
        versionFetcher: (_) async => throw StateError('not called'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Servers (0)'), findsOneWidget);
      expect(find.textContaining('No servers connected'), findsOneWidget);
    });

    testWidgets('shows backend version for each connected server',
        (tester) async {
      final manager = _serverManager()
        ..addServer(
          serverId: 'http://example.test:8000',
          serverUrl: Uri.parse('http://example.test:8000'),
          requiresAuth: false,
        );

      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: manager,
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (e) async => const BackendVersionInfo(
          soliplexVersion: '0.36.dev0',
          packageVersions: {'fastapi': '0.124.0'},
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Servers (1)'), findsOneWidget);
      expect(find.text('http://example.test:8000'), findsOneWidget);
      expect(find.text('Backend version: 0.36.dev0'), findsOneWidget);
      expect(find.text('View packages'), findsOneWidget);
    });

    testWidgets('shows Unavailable when fetch fails', (tester) async {
      final manager = _serverManager()
        ..addServer(
          serverId: 'http://broken.test:8000',
          serverUrl: Uri.parse('http://broken.test:8000'),
          requiresAuth: false,
        );

      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: manager,
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (_) async => throw Exception('boom'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('error tile shows retry button that refetches', (tester) async {
      final manager = _serverManager()
        ..addServer(
          serverId: 'http://flaky.test:8000',
          serverUrl: Uri.parse('http://flaky.test:8000'),
          requiresAuth: false,
        );

      var attempt = 0;
      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: manager,
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (_) async {
          attempt++;
          if (attempt == 1) throw Exception('boom');
          return const BackendVersionInfo(
            soliplexVersion: '0.36.dev0',
            packageVersions: {},
          );
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('Backend version: 0.36.dev0'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('App row copy button is disabled while flavor version loads',
        (tester) async {
      final completer = Completer<String>();
      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: _serverManager(),
        versionLoader: () => completer.future,
        versionFetcher: (_) async => throw StateError('not called'),
      )));
      await tester.pump();

      final copyIcon = find.descendant(
        of: find.widgetWithText(ListTile, 'App'),
        matching: find.byIcon(Icons.copy),
      );
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: copyIcon, matching: find.byType(IconButton)),
      );
      expect(iconButton.onPressed, isNull);

      completer.complete('0.0.46+48');
      await tester.pumpAndSettle();
    });

    testWidgets('View packages button is disabled while backend version loads',
        (tester) async {
      final completer = Completer<BackendVersionInfo>();
      final manager = _serverManager()
        ..addServer(
          serverId: 'http://slow.test:8000',
          serverUrl: Uri.parse('http://slow.test:8000'),
          requiresAuth: false,
        );

      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: manager,
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (_) => completer.future,
      )));
      await tester.pump();

      final viewPackages = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'View packages'),
      );
      expect(viewPackages.onPressed, isNull);

      completer.complete(const BackendVersionInfo(
        soliplexVersion: '0.36.dev0',
        packageVersions: {},
      ));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'each tile keeps its own version after a server is removed',
      (tester) async {
        final manager = _serverManager()
          ..addServer(
            serverId: 'http://a.test:8000',
            serverUrl: Uri.parse('http://a.test:8000'),
            requiresAuth: false,
          )
          ..addServer(
            serverId: 'http://b.test:8000',
            serverUrl: Uri.parse('http://b.test:8000'),
            requiresAuth: false,
          );

        await tester.pumpWidget(_buildApp(VersionsScreen(
          appName: 'Acme',
          serverManager: manager,
          versionLoader: () async => '0.0.46+48',
          versionFetcher: (entry) async => BackendVersionInfo(
            soliplexVersion:
                entry.serverId.contains('a.test') ? 'A-1.0.0' : 'B-2.0.0',
            packageVersions: const {},
          ),
        )));
        await tester.pumpAndSettle();

        expect(find.text('Backend version: A-1.0.0'), findsOneWidget);
        expect(find.text('Backend version: B-2.0.0'), findsOneWidget);

        manager.removeServer('http://a.test:8000');
        await tester.pumpAndSettle();

        expect(find.text('http://b.test:8000'), findsOneWidget);
        expect(find.text('Backend version: B-2.0.0'), findsOneWidget);
        expect(find.text('http://a.test:8000'), findsNothing);
        expect(find.text('Backend version: A-1.0.0'), findsNothing);
      },
    );
  });
}
