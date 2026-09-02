import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'route_module.dart';

ThemeData _lightTheme() => buildSoliplexThemeData(
      colors: lightSoliplexColors,
      brightness: Brightness.light,
    );

void main() {
  test('a rejected configuration is recorded, reason and all', () async {
    // The boot screen shows this same text, but reaching it means runApp
    // succeeded. The record is what is left when it did not, so the reason has
    // to be in the message: no sink installLogSinks installs renders
    // attributes, and 'Configuration rejected' alone names nothing.
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(LogManager.instance.reset);

    expect(
      () => ShellConfig.fromModules(
        modules: [
          RouteModule(const ['/'])
        ],
        appName: 'Test',
        lightTheme: ThemeData(), // bare: no SoliplexTheme extension
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      sink.records.single.message,
      contains('buildSoliplexThemeData'),
      reason: 'the reason travels in the message, not an unrendered attribute',
    );
  });

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

    test('a module that cannot even name itself still reports its failure',
        () async {
      // namespace is a getter a module author implements, so it can throw —
      // and it is read while composing the teardown record. Two ways to get
      // this wrong, and only one of them strands anything: reading it outside a
      // guard escapes the loop, and guarding the whole record instead drops the
      // teardown failure. Both are asserted, because a module holding a
      // ServerManager that was never released is worth a record either way.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(LogManager.instance.reset);

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

      final teardown = sink.records
          .where((r) => r.message.contains('Module teardown failed'));
      expect(teardown, hasLength(1), reason: 'the failure was still recorded');
      expect(
        teardown.single.message,
        contains('StateError'),
        reason: 'and says what failed, not only that something did',
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

/// Fails while contributing, so the modules registered before it are built and
/// the ones after it are not.
class _ThrowingBuildModule extends AppModule {
  @override
  String get namespace => 'throws-in-build';

  @override
  ModuleRoutes build() => throw StateError('build failed');
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
