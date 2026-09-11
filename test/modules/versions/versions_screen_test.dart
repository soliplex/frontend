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

/// A screen holding one server whose address needs the full tile width to
/// render on a phone.
Widget _screenWithOneServer() {
  final manager = _serverManager()
    ..addServer(
      serverId: 'https://rag.example.test',
      serverUrl: Uri.parse('https://rag.example.test'),
      requiresAuth: false,
    );

  return VersionsScreen(
    appName: 'Acme',
    serverManager: manager,
    versionLoader: () async => '0.0.46+48',
    versionFetcher: (_) async => const BackendVersionInfo(
      soliplexVersion: '0.36.dev0',
      packageVersions: {},
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_buildApp(child));
  await tester.pumpAndSettle();
}

Rect _copyButtonIn(WidgetTester tester, Finder tile) => tester.getRect(
      find.descendant(of: tile, matching: find.byIcon(Icons.copy)),
    );

void main() {
  group('VersionsScreen', () {
    testWidgets('shows the branded bar without the about button',
        (tester) async {
      await tester.pumpWidget(_buildApp(VersionsScreen(
        appName: 'Acme',
        serverManager: _serverManager(),
        versionLoader: () async => '0.0.46+48',
        versionFetcher: (_) async => throw StateError('not called'),
      )));
      await tester.pumpAndSettle();

      // Branded app name shows in the bar; the about/versions button is
      // dropped because we are already on the versions destination.
      expect(find.text('Acme'), findsOneWidget);
      expect(find.byTooltip('Diagnostics & versions'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

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

    testWidgets('server tile keeps its actions beside the address when wide',
        (tester) async {
      await _pumpAt(tester, const Size(900, 600), _screenWithOneServer());

      final viewPackages = tester.getRect(
        find.widgetWithText(TextButton, 'View packages'),
      );
      final version = tester.getRect(find.text('Backend version: 0.36.dev0'));

      expect(viewPackages.top, lessThan(version.bottom));

      // Right-aligned, which is what keeps this tile's copy button in the
      // same column as the one on every row above it.
      expect(
        _copyButtonIn(tester, find.byType(ListTile).last).left,
        _copyButtonIn(tester, find.widgetWithText(ListTile, 'App')).left,
      );
    });

    testWidgets('server tile stacks its actions under the address when narrow',
        (tester) async {
      await _pumpAt(tester, const Size(320, 600), _screenWithOneServer());

      final address = tester.getRect(find.text('https://rag.example.test'));
      final version = tester.getRect(find.text('Backend version: 0.36.dev0'));
      final viewPackages = tester.getRect(
        find.widgetWithText(TextButton, 'View packages'),
      );

      expect(viewPackages.top, greaterThanOrEqualTo(version.bottom));
      expect(viewPackages.left, address.left);

      // The actions break among themselves too, rather than overflowing.
      expect(
        _copyButtonIn(tester, find.byType(ListTile).last).top,
        greaterThanOrEqualTo(viewPackages.bottom),
      );
    });

    testWidgets('server tile version line takes the themed subtitle style',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(900, 600),
        ListTileTheme(
          data: const ListTileThemeData(
            subtitleTextStyle: TextStyle(
              fontSize: 31,
              fontStyle: FontStyle.italic,
            ),
          ),
          child: _screenWithOneServer(),
        ),
      );

      final style = tester
          .widget<EditableText>(find.text('Backend version: 0.36.dev0'))
          .style;
      expect(style.fontSize, 31);
      expect(style.fontStyle, FontStyle.italic);
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
