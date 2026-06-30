import 'package:flutter/foundation.dart';

/// A resolved font family plus its fallback chain, ready to drop into a
/// `TextStyle`'s `fontFamily` / `fontFamilyFallback`.
@immutable
class ResolvedFont {
  const ResolvedFont({this.fontFamily, this.fontFamilyFallback = const []});

  final String? fontFamily;
  final List<String> fontFamilyFallback;

  @override
  bool operator ==(Object other) =>
      other is ResolvedFont &&
      other.fontFamily == fontFamily &&
      listEquals(other.fontFamilyFallback, fontFamilyFallback);

  @override
  int get hashCode =>
      Object.hash(fontFamily, Object.hashAll(fontFamilyFallback));
}

/// Resolves a font-family name (plus fallbacks) to a usable [ResolvedFont].
///
/// The seam that keeps `soliplex_design` dependency-free: the bundled default
/// trusts native asset-font resolution, while a consumer that wants arbitrary
/// fonts (e.g. via `google_fonts`) injects its own implementation at
/// theme-build time.
// A class, not a typedef: it is the public injection seam consumers subclass.
// ignore: one_member_abstracts
abstract class FontResolver {
  const FontResolver();

  /// Resolves a font-family name (plus fallbacks) to a usable [ResolvedFont].
  ///
  /// An implementation MAY load the font as a side effect — e.g. a
  /// `google_fonts`-backed resolver registers a font loader and returns the
  /// family name it registered under. Resolution is synchronous: the theme
  /// layer cannot await a load or verify that a family actually renders.
  /// A consumer that must avoid a flash of fallback text should await font
  /// readiness in `main()` before `runApp` (e.g. `GoogleFonts.pendingFonts()`),
  /// because lowering is intentionally synchronous.
  ResolvedFont resolve(String family, List<String> fallbacks);
}

/// The default resolver. It performs no lookup of its own: families declared
/// in the consumer's `pubspec.yaml` resolve through Flutter's native asset
/// font machinery, so this works offline and in airgapped environments.
///
/// A family that is not bundled (or is misspelled) falls back to the platform
/// default font with no load-time signal — Flutter resolves font assets lazily
/// at render, so the theme layer cannot verify a family exists. Confirm a
/// custom font actually renders by eye.
class BundledFontResolver extends FontResolver {
  const BundledFontResolver();

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) =>
      ResolvedFont(fontFamily: family, fontFamilyFallback: fallbacks);
}
