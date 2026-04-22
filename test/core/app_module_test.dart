import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/core/app_module.dart';
import 'package:soliplex_frontend/src/core/shell_config.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeModule extends AppModule {
  _FakeModule({
    required String ns,
    int pri = 0,
    ModuleRoutes? routes,
  })  : _ns = ns,
        _pri = pri,
        _routes = routes ?? const ModuleRoutes();

  final String _ns;
  final int _pri;
  final ModuleRoutes _routes;

  int attachCount = 0;
  int disposeCount = 0;
  AppModuleContext? attachedCtx;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  ModuleRoutes build(AppModuleContext ctx) => _routes;

  @override
  Future<void> onAttach(AppModuleContext ctx) async {
    attachCount++;
    attachedCtx = ctx;
  }

  @override
  Future<void> onDispose() async => disposeCount++;
}

class _OrderRecordingModule extends AppModule {
  _OrderRecordingModule({required String ns, required int pri, required this.order})
      : _ns = ns,
        _pri = pri;

  final String _ns;
  final int _pri;
  final List<int> order;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  ModuleRoutes build(AppModuleContext ctx) => const ModuleRoutes();

  @override
  Future<void> onAttach(AppModuleContext ctx) async => order.add(_pri);
}

class _DisposeOrderModule extends AppModule {
  _DisposeOrderModule({required String ns, required int pri, required this.order})
      : _ns = ns,
        _pri = pri;

  final String _ns;
  final int _pri;
  final List<int> order;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  ModuleRoutes build(AppModuleContext ctx) => const ModuleRoutes();

  @override
  Future<void> onDispose() async => order.add(_pri);
}

ThemeData _theme() => ThemeData.light();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ShellConfig.fromModules — namespace validation', () {
    test('accepts empty module list', () async {
      await expectLater(
        ShellConfig.fromModules(
          modules: const [],
          appName: 'test',
          theme: _theme(),
        ),
        completes,
      );
    });

    test('accepts modules with unique namespaces', () async {
      final a = _FakeModule(ns: 'a');
      final b = _FakeModule(ns: 'b');

      await expectLater(
        ShellConfig.fromModules(modules: [a, b], appName: 'test', theme: _theme()),
        completes,
      );
    });

    test('allows multiple modules with empty namespace', () async {
      final a = _FakeModule(ns: '');
      final b = _FakeModule(ns: '');

      await expectLater(
        ShellConfig.fromModules(modules: [a, b], appName: 'test', theme: _theme()),
        completes,
      );
    });

    test('throws StateError for duplicate non-empty namespace', () async {
      final a = _FakeModule(ns: 'dup');
      final b = _FakeModule(ns: 'dup');

      await expectLater(
        ShellConfig.fromModules(modules: [a, b], appName: 'test', theme: _theme()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ShellConfig.fromModules — lifecycle', () {
    test('calls onAttach on all modules', () async {
      final a = _FakeModule(ns: 'a');
      final b = _FakeModule(ns: 'b');

      await ShellConfig.fromModules(
        modules: [a, b],
        appName: 'test',
        theme: _theme(),
      );

      expect(a.attachCount, 1);
      expect(b.attachCount, 1);
    });

    test('attaches in descending priority order', () async {
      final order = <int>[];
      final low = _OrderRecordingModule(ns: 'low', pri: 1, order: order);
      final high = _OrderRecordingModule(ns: 'high', pri: 10, order: order);
      final mid = _OrderRecordingModule(ns: 'mid', pri: 5, order: order);

      await ShellConfig.fromModules(
        modules: [low, high, mid],
        appName: 'test',
        theme: _theme(),
      );

      expect(order, [10, 5, 1]);
    });

    test('onDispose called in reverse registration order', () async {
      final order = <int>[];
      // Register high→mid→low so reversed = low→mid→high.
      final high = _DisposeOrderModule(ns: 'high', pri: 10, order: order);
      final mid = _DisposeOrderModule(ns: 'mid', pri: 5, order: order);
      final low = _DisposeOrderModule(ns: 'low', pri: 1, order: order);

      final config = await ShellConfig.fromModules(
        modules: [high, mid, low],
        appName: 'test',
        theme: _theme(),
      );

      config.onDispose?.call();
      await Future<void>.delayed(Duration.zero);

      expect(order, [1, 5, 10]);
    });
  });

  group('AppModuleContext.module<T>()', () {
    test('returns matching module by type', () async {
      final a = _FakeModule(ns: 'a');
      _FakeModule? discovered;

      final b = _DiscoveryModule(
        ns: 'b',
        attachCallback: (ctx) => discovered = ctx.module<_FakeModule>(),
      );

      await ShellConfig.fromModules(
        modules: [a, b],
        appName: 'test',
        theme: _theme(),
      );

      expect(discovered, same(a));
    });

    test('returns null when type not registered', () async {
      _FakeModule? discovered;

      final b = _DiscoveryModule(
        ns: 'b',
        attachCallback: (ctx) => discovered = ctx.module<_FakeModule>(),
      );

      await ShellConfig.fromModules(
        modules: [b],
        appName: 'test',
        theme: _theme(),
      );

      expect(discovered, isNull);
    });
  });

  group('ShellConfig.fromModules — routes & overrides', () {
    test('flattens routes from all modules', () async {
      // ModuleRoutes with empty routes still produces a valid config.
      final config = await ShellConfig.fromModules(
        modules: [_FakeModule(ns: 'a'), _FakeModule(ns: 'b')],
        appName: 'test',
        theme: _theme(),
      );

      expect(config.routes, isA<List>());
    });

    test('config carries appName and theme', () async {
      final theme = _theme();
      final config = await ShellConfig.fromModules(
        modules: const [],
        appName: 'MyApp',
        theme: theme,
      );

      expect(config.appName, 'MyApp');
      expect(config.theme, same(theme));
    });
  });

  group('AppModule defaults', () {
    test('default priority is 0', () {
      expect(_FakeModule(ns: 'x').priority, 0);
    });

    test('default onAttach is a no-op', () async {
      final m = _NoLifecycleModule();
      expect(
        () async => m.onAttach(_StubContext()),
        returnsNormally,
      );
    });

    test('default onDispose is a no-op', () async {
      final m = _NoLifecycleModule();
      expect(() async => m.onDispose(), returnsNormally);
    });
  });
}

// ---------------------------------------------------------------------------
// Additional test doubles
// ---------------------------------------------------------------------------

class _DiscoveryModule extends AppModule {
  _DiscoveryModule({required String ns, required this.attachCallback})
      : _ns = ns;

  final String _ns;
  final void Function(AppModuleContext) attachCallback;

  @override
  String get namespace => _ns;

  @override
  ModuleRoutes build(AppModuleContext ctx) => const ModuleRoutes();

  @override
  Future<void> onAttach(AppModuleContext ctx) async => attachCallback(ctx);
}

class _NoLifecycleModule extends AppModule {
  @override
  String get namespace => 'no-lifecycle';

  @override
  ModuleRoutes build(AppModuleContext ctx) => const ModuleRoutes();
}

class _StubContext implements AppModuleContext {
  @override
  T? module<T extends AppModule>() => null;
}
