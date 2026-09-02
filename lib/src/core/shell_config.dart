import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'app_module.dart';
import 'inactivity/inactivity_config.dart';
import 'router.dart';
import 'status_message_config.dart';

/// A failure carrying a [diagnosis] this package composed, safe to show whole.
///
/// The boot-failure surface renders [diagnosis] verbatim and reduces every
/// other exception to a type name, because an exception escaping the same
/// assembly can carry the value it failed on and that surface needs no
/// navigation and no export to read. Implementing this is what claims a message
/// is safe to display; do not implement it over a value a user or a backend
/// supplied.
///
/// It has to be a type rather than a convention because `describeFailure`
/// reduces both an [ArgumentError] carrying no `name` and a [StateError] to a
/// bare type name, taking the diagnosis with it. It is an interface rather than
/// a base class because the two failures that carry one differ in what they
/// are: a rejected argument and a flavor used twice. Both keep the base class
/// their callers already catch and their docs already name.
abstract interface class ShellDiagnosis {
  String get diagnosis;
}

/// Records [message] and returns the error to throw with it.
///
/// The record is a second copy, not the only one: the boot surface shows the
/// same text, but reaching it means `runApp` succeeded, and a device where it
/// did not is exactly where a log is the last thing left. The reason travels in
/// the record's message because no sink `installLogSinks` installs renders
/// attributes — memory, console and stdout all format the message alone — so an
/// attribute would reach only a buffer whose one reader is the diagnostics
/// screen, which a failed boot never navigates to. Every caller composes
/// [message] in code, so it is safe to record whole.
ShellConfigurationError _rejected(String message) {
  LogManager.instance
      .getLogger('soliplex.shell')
      .error('Configuration rejected: $message');
  return ShellConfigurationError._(message);
}

/// Thrown when a [ShellConfig] cannot be assembled — an invalid route
/// configuration, a theme missing its extension, a duplicated namespace.
///
/// Extends [ArgumentError] so callers catching the general case still do.
/// `final` with a private constructor so [_rejected] is the only place one is
/// built: the claim [ShellDiagnosis] makes is about the string, and a type any
/// caller could construct would let a module put its own text on that screen.
final class ShellConfigurationError extends ArgumentError
    implements ShellDiagnosis {
  ShellConfigurationError._(String super.message);

  @override
  String get diagnosis => message as String;
}

class ShellConfig {
  final String appName;
  final ThemeData lightTheme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;
  final String initialRoute;
  final Listenable? refreshListenable;
  final InactivityConfig inactivity;
  final StatusMessageConfig statusMessage;

  /// Tears down every module's `onDispose` in reverse registration order.
  ///
  /// **Caller responsibility.** The shell widget does not invoke this —
  /// it owns neither the config nor the modules. Callers that need
  /// deterministic teardown (tests, embedded library consumers, future
  /// lifecycle-owner wrappers) must `await shellConfig.dispose()`
  /// themselves. Standalone apps (`runSoliplexShell` + process exit)
  /// rely on OS reclamation.
  final Future<void> Function() dispose;

  final List<RouteBase> _routes;
  final List<Override> _overrides;
  final List<GoRouterRedirect> _redirects;
  final Set<String> _publicPaths;

  ShellConfig._internal({
    required this.appName,
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
    required this.initialRoute,
    required List<RouteBase> routes,
    required List<Override> overrides,
    required List<GoRouterRedirect> redirects,
    required Set<String> publicPaths,
    required this.refreshListenable,
    required this.inactivity,
    required this.statusMessage,
    required this.dispose,
  })  : _routes = List.unmodifiable(routes),
        _overrides = List.unmodifiable(overrides),
        _redirects = List.unmodifiable(redirects),
        _publicPaths = Set.unmodifiable(publicPaths);

  List<RouteBase> get routes => _routes;
  List<Override> get overrides => _overrides;
  List<GoRouterRedirect> get redirects => _redirects;

  /// Paths every module declared reachable without a session, composed.
  Set<String> get publicPaths => _publicPaths;

  /// Creates a [ShellConfig] from a list of [AppModule] instances.
  ///
  /// Calls [AppModule.build] on each module in registration order to
  /// collect routes and overrides. The returned config's [dispose] runs
  /// [AppModule.onDispose] in reverse registration order; invoking it is
  /// the caller's responsibility (see [dispose]).
  ///
  /// The passed [modules] are consumed here — do not reuse the same live
  /// instances across two calls, or both configs' [dispose] will run over
  /// them.
  ///
  /// Throws [ArgumentError] when a theme lacks the [SoliplexTheme] extension,
  /// a namespace is duplicated, or the route configuration is invalid —
  /// an invalid [ShellConfig] cannot be constructed. Any abort schedules the
  /// [modules]' teardown on its way out — including one raised by a module's
  /// own [AppModule.build] — because they hold what they were constructed with
  /// whether or not assembly reached building them. The [modules] are spent
  /// either way.
  static ShellConfig fromModules({
    required List<AppModule> modules,
    required String appName,
    required ThemeData lightTheme,
    ThemeData? darkTheme,
    ThemeMode themeMode = ThemeMode.system,
    String initialRoute = '/',
    String? signedOutLandingPath,
    Listenable? refreshListenable,
    InactivityConfig inactivity = const InactivityConfig(),
    StatusMessageConfig statusMessage = const StatusMessageConfig(),
  }) {
    try {
      if (lightTheme.extension<SoliplexTheme>() == null) {
        throw _rejected(
          'The lightTheme is missing the SoliplexTheme extension. Build it '
          'with buildSoliplexThemeData(...), not a bare ThemeData(...).',
        );
      }
      if (darkTheme != null && darkTheme.extension<SoliplexTheme>() == null) {
        throw _rejected(
          'The darkTheme is missing the SoliplexTheme extension. Build it '
          'with buildSoliplexThemeData(...), not a bare ThemeData(...).',
        );
      }
      final coordinator = _AppModuleCoordinator(modules);
      final routes = coordinator.routes;
      final routeErrors = [
        ...validateRoutes(
          routes: routes,
          initialRoute: initialRoute,
          publicPaths: coordinator.publicPaths,
          signedOutLandingPath: signedOutLandingPath,
        ),
        ...validateModulePublicPaths(coordinator.contributions),
      ];
      if (routeErrors.isNotEmpty) {
        throw _rejected(
            'Invalid route configuration:\n${routeErrors.join('\n')}');
      }
      return ShellConfig._internal(
        appName: appName,
        lightTheme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        initialRoute: initialRoute,
        routes: routes,
        overrides: coordinator.overrides,
        redirects: coordinator.redirects,
        publicPaths: coordinator.publicPaths,
        refreshListenable: refreshListenable,
        inactivity: inactivity,
        statusMessage: statusMessage,
        dispose: coordinator.disposeAll,
      );
    } catch (_) {
      // Any abort above leaves the modules holding what they were constructed
      // with — a ServerManager, HTTP clients, an inspector — and returns no
      // ShellConfig, so nothing hands the caller a dispose for them.
      // Fired rather than awaited because this is synchronous; a failure inside
      // it is recorded by disposeModules itself and swallowed here, so it
      // cannot arrive alongside and obscure the error being rethrown.
      unawaited(_disposeModules(modules).catchError((Object _) {}));
      rethrow;
    }
  }
}

/// Tears [modules] down in reverse registration order, **continuing past a
/// failure**. Stopping at the first one strands every module registered before
/// it — on the standard flavor a throw in the room module would skip auth and
/// diagnostics, which are the ones holding the server connections, the HTTP
/// clients and the inspector, so the teardown would abandon exactly what it
/// exists to release.
///
/// Each failure is recorded with the namespace that produced it, because a
/// stack trace names a frame and not which module it belonged to, and the
/// module travels in the message because no sink `installLogSinks` installs
/// renders attributes. One of them is rethrown once the rest have run, so a
/// caller awaiting [ShellConfig.dispose] still learns that teardown was not
/// clean.
Future<void> _disposeModules(List<AppModule> modules) async {
  Object? firstError;
  StackTrace? firstStack;
  for (final m in modules.reversed) {
    try {
      await m.onDispose();
    } catch (error, stackTrace) {
      // `namespace` is a getter a module author implements, so naming the
      // module can itself throw. Only that read is guarded, and it falls back
      // rather than giving up: a throw anywhere else in this catch escapes the
      // loop and strands every module not yet reached, while swallowing the
      // whole record would lose the teardown failure this clause exists to
      // report.
      String module;
      try {
        module = m.namespace.isEmpty ? '<anonymous>' : m.namespace;
      } catch (_) {
        module = '<${m.runtimeType}: namespace threw>';
      }
      LogManager.instance.getLogger('soliplex.shell').warning(
            'Module teardown failed for $module: ${describeFailure(error)}',
            attributes: {'module': module, 'failure': describeFailure(error)},
            stackTrace: stackTrace,
          );
      firstError ??= error;
      firstStack ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStack!);
  }
}

// ---------------------------------------------------------------------------
// Internal coordinator — not part of the public API.
// ---------------------------------------------------------------------------

class _AppModuleCoordinator {
  _AppModuleCoordinator(List<AppModule> modules) {
    final seen = <String>{};
    for (final m in modules) {
      if (m.namespace.isNotEmpty && !seen.add(m.namespace)) {
        throw _rejected('Duplicate AppModule namespace: "${m.namespace}"');
      }
    }
    _modules = List.unmodifiable(modules);
    _built = _modules.map((m) => m.build()).toList(growable: false);
  }

  late final List<AppModule> _modules;
  late final List<ModuleRoutes> _built;

  Future<void> disposeAll() => _disposeModules(_modules);

  List<RouteBase> get routes => _built.expand((r) => r.routes).toList();

  List<Override> get overrides => _built.expand((r) => r.overrides).toList();

  List<GoRouterRedirect> get redirects =>
      _built.map((r) => r.redirect).nonNulls.toList();

  /// Computed once: fromModules reads this twice, to validate and to store.
  late final Set<String> publicPaths =
      _built.expand((r) => r.publicPaths).toSet();

  /// Each module's contribution paired with the namespace that made it, so a
  /// declaration can be attributed back to its author.
  List<({String namespace, ModuleRoutes contribution})> get contributions => [
        for (var i = 0; i < _modules.length; i++)
          (namespace: _modules[i].namespace, contribution: _built[i]),
      ];
}
