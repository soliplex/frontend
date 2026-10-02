import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/router.dart'
    show platformStartLocation;

/// One labelled page per path, so a test can tell which route rendered. Each
/// builder reads its query, as the app's home, lobby and diagnostics routes
/// do, so an undecodable query throws here the way it does in production.
class _LabeledModule extends AppModule {
  @override
  String get namespace => 'labeled';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          for (final path in [
            '/',
            '/lobby',
            '/auth/callback',
            '/room/:alias/:id',
          ])
            GoRoute(
              path: path,
              builder: (_, state) {
                state.uri.queryParameters;
                return Text('route $path');
              },
            ),
        ],
      );
}

Future<void> _boot(
  WidgetTester tester,
  String platformRoute, {
  String initialRoute = '/lobby',
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = platformRoute;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final config = ShellConfig.fromModules(
    modules: [_LabeledModule()],
    appName: 'Test',
    lightTheme: buildSoliplexThemeData(
      colors: lightSoliplexColors,
      brightness: Brightness.light,
    ),
    initialRoute: initialRoute,
  );
  final router = buildRouter(config);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  group('buildRouter start address', () {
    testWidgets(
        'starts at / and logs one warning when the platform route '
        'does not decode', (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      await _boot(tester, '/room/%FF/x');

      expect(find.text('route /'), findsOneWidget);
      final record = sink.records
          .where((r) =>
              r.loggerName == 'soliplex.router' && r.level == LogLevel.warning)
          .single;
      expect(record.message, 'Ignored a start address that cannot be decoded');
    });

    testWidgets(
        'starts at / when the platform route does not parse, '
        'and logs no part of it', (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      await _boot(tester, '//room:x/y');

      expect(find.text('route /'), findsOneWidget);
      final record = sink.records
          .where((r) =>
              r.loggerName == 'soliplex.router' && r.level == LogLevel.warning)
          .single;
      expect(record.toString(), isNot(contains('room')));
      expect(record.toString(), isNot(contains('//room:x/y')));
    });

    testWidgets('starts at / for an undecodable query', (tester) async {
      await _boot(tester, '/lobby?server=%FF');

      expect(find.text('route /'), findsOneWidget);
    });

    testWidgets('opens a valid deep link', (tester) async {
      await _boot(tester, '/room/a/b');

      expect(find.text('route /room/:alias/:id'), findsOneWidget);
    });

    testWidgets('starts at the initial route when the platform says /',
        (tester) async {
      await _boot(tester, '/');

      expect(find.text('route /lobby'), findsOneWidget);
    });

    testWidgets('a callback boot still lands on the callback route',
        (tester) async {
      await _boot(tester, '/auth/callback', initialRoute: '/auth/callback');

      expect(find.text('route /auth/callback'), findsOneWidget);
    });

    testWidgets('an unknown route boots without an exception', (tester) async {
      await _boot(tester, '/no-such-page');

      expect(tester.takeException(), isNull);
      expect(find.textContaining(RegExp(r'^route ')), findsNothing);
    });
  });

  group('platformStartLocation', () {
    String start(String route) =>
        platformStartLocation(route, initialRoute: '/lobby');

    test('keeps a valid deep link with its query', () {
      expect(start('/room/a/b?x=1'), '/room/a/b?x=1');
    });

    test('a platform route of / means the initial route', () {
      expect(start('/'), '/lobby');
    });

    test('an empty platform route means the initial route', () {
      expect(start(''), '/lobby');
    });

    test('keeps a query on the home path', () {
      expect(start('/?url=x'), '/?url=x');
    });

    test('reads a bare query as the home path', () {
      expect(start('?a=b'), '/?a=b');
    });

    test('keeps an escape that parses as a literal percent', () {
      expect(start('/room/%ZZ/x'), '/room/%25ZZ/x');
    });

    for (final route in [
      '/room/%FF/x',
      '/versions/server/%FF',
      '/lobby?server=%FF',
      '/?url=%FF',
      '//room:x/y',
    ]) {
      test('throws for $route', () {
        expect(() => start(route), throwsFormatException);
      });
    }
  });
}
