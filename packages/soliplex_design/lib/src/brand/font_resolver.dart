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

  ResolvedFont resolve(String family, List<String> fallbacks);
}

/// The default resolver. It performs no lookup of its own: families declared
/// in the consumer's `pubspec.yaml` resolve through Flutter's native asset
/// font machinery, so this works offline and in airgapped environments.
class BundledFontResolver extends FontResolver {
  const BundledFontResolver();

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) =>
      ResolvedFont(fontFamily: family, fontFamilyFallback: fallbacks);
}
