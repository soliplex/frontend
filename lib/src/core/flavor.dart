import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'app_identity.dart';
import 'app_module.dart';
import 'inactivity/inactivity_config.dart';
import 'shell_config.dart';

/// The theme half of a [Flavor]: what the app looks like, before lowering.
///
/// One slot wrapping the two public theming paths, plus [mode] — brightness
/// policy travels with the themes it selects between:
///
/// - [FlavorTheme.brand] — the curated [BrandTheme] contract (ADR-002). The
///   brand is held as-is and lowered when the flavor builds, so this slot
///   stays cheap to construct and `const`-friendly.
/// - [FlavorTheme.themeData] — [ThemeData] that must be built with
///   `buildSoliplexThemeData`, for a fork taking full token control
///   (ADR-003 §1.3). A bare `ThemeData()` compiles but is rejected when the
///   flavor builds, since it lacks the required [SoliplexTheme] extension.
class FlavorTheme {
  const FlavorTheme.brand(
    BrandTheme this._brand, {
    FontResolver fontResolver = const BundledFontResolver(),
    ClassificationTheme? classifications,
    this.mode = ThemeMode.system,
  })  : _fontResolver = fontResolver,
        _classifications = classifications,
        _light = null,
        _dark = null;

  const FlavorTheme.themeData({
    required ThemeData light,
    ThemeData? dark,
    this.mode = ThemeMode.system,
  })  : _brand = null,
        _fontResolver = const BundledFontResolver(),
        _classifications = null,
        _light = light,
        _dark = dark;

  final BrandTheme? _brand;
  final ThemeMode mode;
  final FontResolver _fontResolver;
  final ClassificationTheme? _classifications;
  final ThemeData? _light;
  final ThemeData? _dark;

  /// Lowers to the concrete light/dark pair. Brand lowering happens here —
  /// once, at build time — so flavors can be composed freely without paying
  /// for it, and both brightnesses are guaranteed to lower with the same
  /// resolver and classifications.
  ({ThemeData light, ThemeData? dark}) _resolve() {
    final brand = _brand;
    if (brand == null) return (light: _light!, dark: _dark);
    return (
      light: lowerBrandTheme(
        brand,
        Brightness.light,
        fontResolver: _fontResolver,
        classifications: _classifications,
      ),
      dark: lowerBrandTheme(
        brand,
        Brightness.dark,
        fontResolver: _fontResolver,
        classifications: _classifications,
      ),
    );
  }
}

/// The complete declaration of a Soliplex app variant — who it is
/// ([identity]), how it looks ([theme]), what it does ([modules]), and how
/// it boots — as a single-use assembly declaration, built once.
///
/// [build] owns the assembly ritual in one place — thread `identity.appName`,
/// resolve [theme] to a light/dark pair (lowering the brand when present) and
/// carry [FlavorTheme.mode], forward the boot knobs
/// ([initialRoute], [refreshListenable], [inactivity]) and [modules] into the
/// [ShellConfig] — so a flavor never re-implements each failable line.
/// Customize by composing with `standardFlavor`. See ADR-003.
class Flavor {
  Flavor({
    required this.identity,
    required this.theme,
    required List<AppModule> modules,
    this.initialRoute = '/',
    this.refreshListenable,
    this.inactivity = const InactivityConfig(),
  }) : modules = List.unmodifiable(modules);

  final AppIdentity identity;
  final FlavorTheme theme;
  final List<AppModule> modules;
  final String initialRoute;

  /// Re-evaluates router redirects when it notifies (e.g. on auth changes).
  final Listenable? refreshListenable;
  final InactivityConfig inactivity;

  bool _built = false;

  /// Lowers the declaration to a boot-ready [ShellConfig] — the blessed place
  /// identity, theme, and the module graph meet.
  ///
  /// The returned config's [ShellConfig.dispose] is the caller's to invoke;
  /// the shell widget never calls it. Embedders that unmount the shell must
  /// retain the config and await `dispose` themselves.
  ///
  /// Throws [StateError] on a second call: [modules] are live instances, so
  /// building again would re-run [AppModule.build] on them and hand back a
  /// second [ShellConfig.dispose] over the same modules.
  ShellConfig build() {
    if (_built) {
      throw StateError(
        'Flavor.build() was already called. A flavor owns live modules and '
        'may be built only once; construct a fresh flavor to build again.',
      );
    }
    _built = true;
    final themes = theme._resolve();
    return ShellConfig.fromModules(
      appName: identity.appName,
      lightTheme: themes.light,
      darkTheme: themes.dark,
      themeMode: theme.mode,
      initialRoute: initialRoute,
      refreshListenable: refreshListenable,
      inactivity: inactivity,
      modules: modules,
    );
  }
}
