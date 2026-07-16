import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';

/// Brand identity for a Soliplex shell: a display name and one or two logo
/// widgets. Visual theming (color, type, shape) is a separate concern — see
/// `BrandTheme` — so identity and theme can vary independently.
///
/// Whitelabel authors construct one of these and hand it to the flavor.
@immutable
class AppIdentity {
  const AppIdentity({
    required this.appName,
    required this.logoLight,
    this.logoDark,
    this.logoGlow,
  })  : assert(appName != '', 'appName must not be empty.'),
        assert(
          logoGlow == null || logoDark == null,
          'logoGlow styles the dark-mode glow fallback and is ignored when '
          'logoDark is provided; set one or the other.',
        );

  /// Used as `MaterialApp.title` and surfaced through the auth + versions
  /// modules.
  final String appName;

  /// Logo widget used in light mode and as the fallback in dark mode when
  /// [logoDark] is not provided.
  final Widget logoLight;

  /// Optional dedicated dark-mode logo. When null, [BrandLogo] renders
  /// [logoLight] wrapped in a [SoliplexGlow] backplate so dark-on-light
  /// institutional marks stay legible against the dark surface.
  final Widget? logoDark;

  /// Glow color for the dark-mode fallback when [logoDark] is null. Ignored
  /// when [logoDark] is provided. When null, [BrandLogo] derives a soft halo
  /// from the active theme's `onSurface`.
  final Color? logoGlow;

  static const _soliplexLogoAsset = 'assets/branding/soliplex/logo_1024.png';
  static const _soliplexLogoSize = 64.0;

  /// Default Soliplex identity. The logo resolves against the running app's
  /// own asset bundle, so this is correct when `soliplex_frontend` is the
  /// runnable app. A consumer that imports `soliplex_frontend` as a library
  /// supplies its own [AppIdentity] with its own logo.
  static AppIdentity get soliplex => AppIdentity(
        appName: 'Soliplex',
        logoLight: Image.asset(
          _soliplexLogoAsset,
          width: _soliplexLogoSize,
          height: _soliplexLogoSize,
        ),
      );
}

/// Renders the brand mark for the current theme brightness, applying a glow
/// backplate when only a single light-mode logo is provided.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.identity});

  /// 8-bit alpha (~0.7 opacity) of the theme-derived fallback halo.
  static const _fallbackGlowAlpha = 179;

  final AppIdentity identity;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light) {
      return identity.logoLight;
    }
    final dark = identity.logoDark;
    if (dark != null) return dark;
    final glow = identity.logoGlow ??
        Theme.of(context).colorScheme.onSurface.withAlpha(_fallbackGlowAlpha);
    return SoliplexGlow(color: glow, child: identity.logoLight);
  }
}
