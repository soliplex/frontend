import 'package:flutter/material.dart';

import 'package:soliplex_design/src/marking/dataset_marking.dart';

/// A single `(background, foreground)` color pair for one classification
/// marking.
///
/// Per the marking guidance the text label is the authoritative cue and
/// color is only secondary — every consumer renders the exact
/// [DatasetMarking.label] text, never color alone.
@immutable
class SoliplexMarkingColor {
  const SoliplexMarkingColor({
    required this.background,
    required this.foreground,
  });

  /// Banner / badge fill.
  final Color background;

  /// Readable label color on top of [background].
  final Color foreground;
}

/// The full palette of classification marking colors, one pair per
/// [DatasetMarking].
///
/// Lives on `SoliplexTheme` so it is reached the standard way
/// (`SoliplexTheme.of(context).markingColors`) and so **white-label builds
/// can override it** — different customers (e.g. AMIA vs AFSOC) mandate
/// different marking palettes. [dod] is the default; a flavor overrides
/// individual markings via [copyWith] and passes the result to
/// `soliplexLightTheme(markingColors: ...)` / `soliplexDarkTheme(...)`.
///
/// Marking colors are intentionally **not** derived from the brand accent
/// or flipped between light and dark: a classification color is
/// authoritative and must read identically everywhere.
@immutable
class SoliplexMarkingColors {
  const SoliplexMarkingColors({
    required this.unclassified,
    required this.cui,
    required this.confidential,
    required this.secret,
    required this.topSecret,
    required this.topSecretSci,
  });

  final SoliplexMarkingColor unclassified;
  final SoliplexMarkingColor cui;
  final SoliplexMarkingColor confidential;
  final SoliplexMarkingColor secret;
  final SoliplexMarkingColor topSecret;
  final SoliplexMarkingColor topSecretSci;

  /// Default DoD-provided palette. White-label flavors start here and
  /// override the markings they need via [copyWith].
  static const SoliplexMarkingColors dod = SoliplexMarkingColors(
    unclassified: SoliplexMarkingColor(
      background: Color(0xFF007A33),
      foreground: Color(0xFFFFFFFF),
    ),
    cui: SoliplexMarkingColor(
      background: Color(0xFF502B85),
      foreground: Color(0xFFFFFFFF),
    ),
    confidential: SoliplexMarkingColor(
      background: Color(0xFF0033A0),
      foreground: Color(0xFFFFFFFF),
    ),
    secret: SoliplexMarkingColor(
      background: Color(0xFFC8102E),
      foreground: Color(0xFFFFFFFF),
    ),
    topSecret: SoliplexMarkingColor(
      background: Color(0xFFFF8C00),
      foreground: Color(0xFF000000),
    ),
    topSecretSci: SoliplexMarkingColor(
      background: Color(0xFFFCE83A),
      foreground: Color(0xFF000000),
    ),
  );

  /// The color pair for [marking].
  SoliplexMarkingColor resolve(DatasetMarking marking) => switch (marking) {
        DatasetMarking.unclassified => unclassified,
        DatasetMarking.cui => cui,
        DatasetMarking.confidential => confidential,
        DatasetMarking.secret => secret,
        DatasetMarking.topSecret => topSecret,
        DatasetMarking.topSecretSci => topSecretSci,
      };

  /// Returns a copy with the given markings replaced — the white-label
  /// override entry point.
  SoliplexMarkingColors copyWith({
    SoliplexMarkingColor? unclassified,
    SoliplexMarkingColor? cui,
    SoliplexMarkingColor? confidential,
    SoliplexMarkingColor? secret,
    SoliplexMarkingColor? topSecret,
    SoliplexMarkingColor? topSecretSci,
  }) {
    return SoliplexMarkingColors(
      unclassified: unclassified ?? this.unclassified,
      cui: cui ?? this.cui,
      confidential: confidential ?? this.confidential,
      secret: secret ?? this.secret,
      topSecret: topSecret ?? this.topSecret,
      topSecretSci: topSecretSci ?? this.topSecretSci,
    );
  }
}
