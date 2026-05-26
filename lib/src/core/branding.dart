import 'package:flutter/material.dart';

import '../design/design.dart';

/// Brand identity for a Soliplex shell: accent colors for light and dark
/// themes, a display name, and one or two logo widgets.
///
/// Whitelabel authors construct one of these and hand it to the flavor.
/// Everything in the design system except the brand-driven `primary` stays
/// Soliplex (surfaces, container tones, status colors, radii, typography) so
/// the platform identity stays legible across flavors.
@immutable
class SoliplexBranding {
  const SoliplexBranding({
    required this.accentLight,
    required this.accentDark,
    required this.appName,
    required this.logoLight,
    this.logoDark,
    this.logoGlow,
  });

  /// Brand accent for the light theme. Drives `primary` and its readable
  /// `onPrimary` foreground via [SoliplexColors.fromAccent]; container tones
  /// and every other slot stay neutral Soliplex.
  final Color accentLight;

  /// Brand accent for the dark theme. Same derivation as [accentLight].
  final Color accentDark;

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

  /// Default Soliplex branding. The logo resolves against the running app's
  /// own asset bundle (the bare asset path), so this is correct when
  /// `soliplex_frontend` is the runnable app. A consumer that imports
  /// `soliplex_frontend` as a library is expected to supply its own
  /// [SoliplexBranding] with its own logo.
  static SoliplexBranding get soliplex => SoliplexBranding(
        accentLight: lightSoliplexColors.primary,
        accentDark: darkSoliplexColors.primary,
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
  const BrandLogo({super.key, required this.branding});

  /// 8-bit alpha (~0.7 opacity) of the theme-derived fallback halo.
  static const _fallbackGlowAlpha = 179;

  final SoliplexBranding branding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light) {
      return branding.logoLight;
    }
    final dark = branding.logoDark;
    if (dark != null) return dark;
    final glow = branding.logoGlow ??
        Theme.of(context).colorScheme.onSurface.withAlpha(_fallbackGlowAlpha);
    return SoliplexGlow(color: glow, child: branding.logoLight);
  }
}
