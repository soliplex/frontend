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
///   brand is held as-is and lowered when the flavor builds, so constructing
///   a flavor stays cheap and `const`-friendly.
/// - [FlavorTheme.themeData] — prebuilt [ThemeData] from
///   `buildSoliplexThemeData`, for a fork taking full token control
///   (ADR-003 §1.3).
class FlavorTheme {
  const FlavorTheme.brand(
    BrandTheme this.brand, {
    this.fontResolver = const BundledFontResolver(),
    this.classifications,
    this.mode = ThemeMode.system,
  })  : _light = null,
        _dark = null;

  const FlavorTheme.themeData({
    required ThemeData light,
    ThemeData? dark,
    this.mode = ThemeMode.system,
  })  : brand = null,
        fontResolver = null,
        classifications = null,
        _light = light,
        _dark = dark;

  final BrandTheme? brand;
  final FontResolver? fontResolver;
  final ClassificationTheme? classifications;
  final ThemeMode mode;
  final ThemeData? _light;
  final ThemeData? _dark;

  /// Lowers to the concrete light/dark pair. Brand lowering happens here —
  /// once, at build time — so flavors can be composed and copied freely
  /// without paying for it, and both brightnesses are guaranteed to lower
  /// with the same resolver and classifications.
  ({ThemeData light, ThemeData? dark}) resolve() {
    final brand = this.brand;
    if (brand == null) return (light: _light!, dark: _dark);
    return (
      light: lowerBrandTheme(
        brand,
        Brightness.light,
        fontResolver: fontResolver!,
        classifications: classifications,
      ),
      dark: lowerBrandTheme(
        brand,
        Brightness.dark,
        fontResolver: fontResolver!,
        classifications: classifications,
      ),
    );
  }
}

/// The complete declaration of a Soliplex app variant — who it is
/// ([identity]), how it looks ([theme]), what it does ([modules]), and how
/// it boots — as a first-class value.
///
/// A flavor used to be a calling convention: any `Future<ShellConfig>`
/// function, each transcribing the same assembly ritual (thread
/// `identity.appName`, lower the brand twice, forward the composition kit's
/// fields) with each line failable. [build] owns that ritual in one place;
/// forks customize by composing a value ([copyWith]) instead of
/// re-implementing it. See ADR-003.
class Flavor {
  const Flavor({
    required this.identity,
    required this.theme,
    required this.modules,
    this.initialRoute = '/',
    this.refreshListenable,
    this.inactivity = const InactivityConfig(),
  });

  final AppIdentity identity;
  final FlavorTheme theme;
  final List<AppModule> modules;
  final String initialRoute;

  /// Re-evaluates router redirects when it notifies (e.g. on auth changes).
  final Listenable? refreshListenable;
  final InactivityConfig inactivity;

  Flavor copyWith({
    AppIdentity? identity,
    FlavorTheme? theme,
    List<AppModule>? modules,
    String? initialRoute,
    Listenable? refreshListenable,
    InactivityConfig? inactivity,
  }) =>
      Flavor(
        identity: identity ?? this.identity,
        theme: theme ?? this.theme,
        modules: modules ?? this.modules,
        initialRoute: initialRoute ?? this.initialRoute,
        refreshListenable: refreshListenable ?? this.refreshListenable,
        inactivity: inactivity ?? this.inactivity,
      );

  /// Lowers the declaration to a boot-ready [ShellConfig] — the single place
  /// identity, theme, and the module graph meet.
  Future<ShellConfig> build() {
    final themes = theme.resolve();
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
