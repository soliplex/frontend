import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show BackendVersionInfo;
import 'package:soliplex_frontend/src/modules/versions/server_versions_screen.dart';

import '../../helpers/test_server_entry.dart';

const _info = BackendVersionInfo(
  soliplexVersion: '0.36.dev0',
  packageVersions: {
    'fastapi': '0.124.0',
    'uvicorn': '0.30.0',
    'soliplex_core': '0.5.1',
  },
);

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ServerVersionsScreen', () {
    testWidgets('renders all packages by default, sorted', (tester) async {
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) async => _info,
      )));
      await tester.pumpAndSettle();

      expect(find.text('3 packages'), findsOneWidget);
      expect(find.text('fastapi'), findsOneWidget);
      expect(find.text('uvicorn'), findsOneWidget);
      expect(find.text('soliplex_core'), findsOneWidget);
    });

    testWidgets('filters packages by search query', (tester) async {
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) async => _info,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'fast');
      await tester.pumpAndSettle();

      expect(find.text('1 of 3 packages'), findsOneWidget);
      expect(find.text('fastapi'), findsOneWidget);
      expect(find.text('uvicorn'), findsNothing);
      expect(find.text('soliplex_core'), findsNothing);
    });

    testWidgets('search is case-insensitive', (tester) async {
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) async => _info,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'FAST');
      await tester.pumpAndSettle();

      expect(find.text('fastapi'), findsOneWidget);
      expect(find.text('1 of 3 packages'), findsOneWidget);
    });

    testWidgets(
      'shows distinct empty state when backend reports zero packages',
      (tester) async {
        await tester.pumpWidget(_wrap(ServerVersionsScreen(
          serverEntry: createTestServerEntry(),
          versionFetcher: (_) async => const BackendVersionInfo(
            soliplexVersion: '0.36.dev0',
            packageVersions: {},
          ),
        )));
        await tester.pumpAndSettle();

        expect(find.text('0 packages'), findsOneWidget);
        expect(find.text('No packages reported'), findsOneWidget);
        expect(find.text('No packages match your search'), findsNothing);
      },
    );

    testWidgets('shows empty-search state', (tester) async {
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) async => _info,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pumpAndSettle();

      expect(find.text('No packages match your search'), findsOneWidget);
    });

    testWidgets('shows progress while loading', (tester) async {
      final completer = Completer<BackendVersionInfo>();
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) => completer.future,
      )));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_info);
      await tester.pumpAndSettle();
    });

    testWidgets('shows error state when fetch fails', (tester) async {
      await tester.pumpWidget(_wrap(ServerVersionsScreen(
        serverEntry: createTestServerEntry(),
        versionFetcher: (_) async => throw Exception('boom'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load version information'), findsOneWidget);
    });
  });
}
