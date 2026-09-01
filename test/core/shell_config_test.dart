import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'route_module.dart';

ThemeData _lightTheme() => buildSoliplexThemeData(
      colors: lightSoliplexColors,
      brightness: Brightness.light,
    );

void main() {
  group('ShellConfig.fromModules theme-extension guard', () {
    test('throws when lightTheme lacks the SoliplexTheme extension', () {
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: ThemeData(), // bare, no SoliplexTheme extension
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when darkTheme lacks the SoliplexTheme extension', () {
      final light = buildSoliplexThemeData(
          colors: lightSoliplexColors, brightness: Brightness.light);
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: light,
          darkTheme: ThemeData(), // bare dark theme, no extension
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShellConfig.fromModules route guard', () {
    test('throws when modules contribute no routes', () {
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: _lightTheme(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when initialRoute matches no route', () {
      expect(
        () => ShellConfig.fromModules(
          modules: [
            RouteModule(const ['/a'])
          ],
          appName: 'Test',
          lightTheme: _lightTheme(),
          initialRoute: '/missing',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Initial route'),
          ),
        ),
      );
    });

    test('rejects a module opening a route another module registers', () {
      // The rule the whole design exists for, reached the way boot reaches it.
      // Unit tests of validateModulePublicPaths cannot see it being wired in:
      // dropping the call from fromModules leaves them all green.
      expect(
        () => ShellConfig.fromModules(
          modules: [
            RouteModule(const ['/one'],
                namespace: 'a', publicPaths: const {'/two'}),
            RouteModule(const ['/two'], namespace: 'b'),
          ],
          appName: 'Test',
          lightTheme: _lightTheme(),
          initialRoute: '/one',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('/two'), contains('"a"')),
          ),
        ),
      );
    });

    test('tears the modules down when the route configuration is rejected',
        () async {
      // The routes it just rejected came from built modules, which hold live
      // resources — HTTP clients, a ServerManager, an inspector. No
      // ShellConfig is returned, so nothing else can ever reach their
      // onDispose, and Flavor refuses a second build over the same instances.
      final disposed = <String>[];

      expect(
        () => ShellConfig.fromModules(
          modules: [
            _DisposeRecordingModule('first', disposed),
            _DisposeRecordingModule('second', disposed),
          ],
          appName: 'Test',
          lightTheme: _lightTheme(),
          initialRoute: '/missing',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Teardown is fired but not awaited: fromModules is synchronous.
      await pumpEventQueue();
      expect(disposed, ['second', 'first'], reason: 'reverse order, as always');
    });
  });
}

/// Records its own teardown, so a failure path can be checked for having run
/// one at all.
class _DisposeRecordingModule extends AppModule {
  _DisposeRecordingModule(this.namespace, this._disposed);

  final List<String> _disposed;

  @override
  final String namespace;

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(path: '/$namespace', builder: (_, __) => const SizedBox()),
        ],
      );

  @override
  Future<void> onDispose() async => _disposed.add(namespace);
}
