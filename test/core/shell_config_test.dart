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

    test('tears down the modules already built when one build() throws',
        () async {
      final disposed = <String>[];

      expect(
        () => ShellConfig.fromModules(
          modules: [
            _DisposeRecordingModule('first', disposed),
            _ThrowingBuildModule(),
          ],
          appName: 'Test',
          lightTheme: _lightTheme(),
        ),
        throwsA(isA<StateError>()),
      );

      await pumpEventQueue();
      expect(disposed, ['first']);
    });

    test('one module failing teardown does not strand the others', () async {
      // Reverse order means a throw in a late-registered module would skip the
      // early ones — which on the standard flavor hold the server connections
      // and HTTP clients this teardown exists to release.
      final disposed = <String>[];
      final config = ShellConfig.fromModules(
        modules: [
          _DisposeRecordingModule('first', disposed),
          _ThrowingDisposeModule(),
          _DisposeRecordingModule('last', disposed),
        ],
        appName: 'Test',
        lightTheme: _lightTheme(),
        initialRoute: '/first',
      );

      await expectLater(config.dispose(), throwsA(isA<StateError>()));
      expect(disposed, ['last', 'first'], reason: 'both sides of the failure');
    });

    test('a module that cannot even name itself does not strand the others',
        () async {
      // namespace is a getter a module author implements, so it can throw —
      // and it is read while composing the teardown record. Composed outside
      // the guard, that throw escapes the loop and strands everything after it.
      final disposed = <String>[];
      final config = ShellConfig.fromModules(
        modules: [
          _DisposeRecordingModule('first', disposed),
          _UnnameableModule(),
        ],
        appName: 'Test',
        lightTheme: _lightTheme(),
        initialRoute: '/first',
      );

      await expectLater(config.dispose(), throwsA(isA<StateError>()));
      expect(disposed, ['first'], reason: 'reached past the unnameable one');
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

/// Fails while contributing, so the modules registered before it are built and
/// the ones after it are not.
class _ThrowingBuildModule extends AppModule {
  @override
  String get namespace => 'throws-in-build';

  @override
  ModuleRoutes build() => throw StateError('build failed');
}

/// Fails during teardown, so the modules on either side of it can be checked
/// for having been disposed anyway.
class _ThrowingDisposeModule extends AppModule {
  @override
  String get namespace => 'throws-on-dispose';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(path: '/$namespace', builder: (_, __) => const SizedBox()),
        ],
      );

  @override
  Future<void> onDispose() async => throw StateError('teardown failed');
}

/// Throws while being described, not while being disposed — the record for a
/// teardown failure has to be composed somewhere, and this is what happens if
/// that somewhere is outside the guard.
class _UnnameableModule extends AppModule {
  var _disposing = false;

  @override
  String get namespace {
    if (_disposing) throw StateError('namespace unavailable');
    return 'unnameable';
  }

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [GoRoute(path: '/u', builder: (_, __) => const SizedBox())],
      );

  @override
  Future<void> onDispose() async {
    _disposing = true;
    throw StateError('teardown failed');
  }
}
