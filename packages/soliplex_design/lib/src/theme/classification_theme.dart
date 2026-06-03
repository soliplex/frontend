import 'dart:developer' as developer;

import 'package:flutter/material.dart';

/// A single configurable confidentiality marking.
///
/// Deployments define their own ordered set of these in flavor code — the
/// design system ships only the mechanism, never a vocabulary. [id] is the
/// stable key (and the future backend value); [label] is the authoritative
/// text, rendered **verbatim** with no uppercasing or transformation.
///
/// [background] / [foreground] are discrete, deployment-chosen colors —
/// deliberately *not* derived from `colorScheme` or the brand accent, so a
/// brand restyling can never silently change the appearance of a security
/// marking. The same instance is used in light and dark (markings do not
/// flip with brightness).
@immutable
class ClassificationLevel {
  const ClassificationLevel({
    required this.id,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  /// Stable key for this level. Unique within a [ClassificationTheme] and
  /// the value a backend would eventually send per room.
  final String id;

  /// Authoritative marking text, rendered verbatim.
  final String label;

  /// Pill background color.
  final Color background;

  /// Pill text/icon color.
  final Color foreground;

  /// Optional leading glyph.
  final IconData? icon;
}

/// Deployment-configurable confidentiality markings, carried on [ThemeData]
/// as a [ThemeExtension] (riding alongside `SoliplexTheme`).
///
/// The [levels] list is **ordered least → most restrictive** — list
/// position *is* the severity. A closed enum could not represent a
/// deployment-defined vocabulary, and an unordered map could not express
/// severity; an ordered list gives both. Resolution and aggregation
/// helpers that consume the ordering are added in a follow-up.
///
/// When no extension is registered, [of] returns [fallback]: a single
/// neutral built-in level. The badge therefore never crashes in a host app
/// running on bare [ThemeData].
class ClassificationTheme extends ThemeExtension<ClassificationTheme> {
  ClassificationTheme({required this.levels, required this.defaultId})
      : assert(levels.isNotEmpty, 'levels must not be empty'),
        assert(
          levels.map((l) => l.id).toSet().length == levels.length,
          'ClassificationLevel ids must be unique',
        ),
        assert(
          levels.any((l) => l.id == defaultId),
          'defaultId must match one of the levels',
        );

  /// Ordered least → most restrictive; list position is the severity.
  final List<ClassificationLevel> levels;

  /// Id of the level applied when a surface supplies no classification.
  /// Required — the deployment decides the err-direction; we never guess.
  final String defaultId;

  /// Resolves [id] to a level. `null` → the [defaultId] level. A known id
  /// → its level. An **unrecognized** id → a fail-loud alarm level built
  /// from `colorScheme.errorContainer`/`onErrorContainer`, carrying the
  /// raw id in its label, plus a `developer.log` warning. An unknown
  /// marking must read as alarming, never as a benign pill.
  ClassificationLevel resolve(BuildContext context, String? id) {
    final effectiveId = id ?? defaultId;
    for (final level in levels) {
      if (level.id == effectiveId) return level;
    }
    return _alarm(context, effectiveId);
  }

  /// The most restrictive level among [ids] by list position. Empty → the
  /// default level. Any unrecognized id → the fail-loud alarm level (an
  /// aggregate containing something unknown must not under-report). `null`
  /// entries count as [defaultId].
  ClassificationLevel highestOf(BuildContext context, Iterable<String?> ids) {
    final list = ids.toList();
    if (list.isEmpty) return resolve(context, null);

    var bestIndex = -1;
    ClassificationLevel? best;
    for (final id in list) {
      final effectiveId = id ?? defaultId;
      final index = levels.indexWhere((l) => l.id == effectiveId);
      if (index < 0) return _alarm(context, effectiveId);
      if (index > bestIndex) {
        bestIndex = index;
        best = levels[index];
      }
    }
    return best!;
  }

  /// Whether [ids] resolve to more than one distinct level. `null` entries
  /// count as [defaultId]; distinct unrecognized ids each count as
  /// themselves.
  bool isMixed(Iterable<String?> ids) {
    return ids.map((id) => id ?? defaultId).toSet().length > 1;
  }

  /// Fail-loud level for an unrecognized id.
  ClassificationLevel _alarm(BuildContext context, String id) {
    developer.log(
      'Unrecognized classification id "$id"; rendering fail-loud alarm '
      'marking.',
      name: 'ClassificationTheme',
      level: 900,
    );
    final scheme = Theme.of(context).colorScheme;
    return ClassificationLevel(
      id: id,
      label: 'UNKNOWN: $id',
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      icon: Icons.error_outline,
    );
  }

  @override
  ClassificationTheme copyWith({
    List<ClassificationLevel>? levels,
    String? defaultId,
  }) {
    return ClassificationTheme(
      levels: levels ?? this.levels,
      defaultId: defaultId ?? this.defaultId,
    );
  }

  /// Markings are discrete, not interpolated — animating between two
  /// confidentiality values would render a meaningless in-between color.
  /// [lerp] snaps to `this` (matching `SoliplexTheme.colors`).
  @override
  ClassificationTheme lerp(covariant ClassificationTheme? other, double t) {
    return this;
  }

  /// Null-safe accessor: falls back to [fallback] when no extension is
  /// registered, so consumers work under bare [ThemeData].
  static ClassificationTheme of(BuildContext context) {
    return Theme.of(context).extension<ClassificationTheme>() ?? fallback;
  }

  /// The single neutral level used by [fallback]. Exposed so consumers can
  /// detect the unconfigured built-in (e.g. to suppress a meaningless pill)
  /// by identity.
  static const ClassificationLevel fallbackLevel = ClassificationLevel(
    id: 'unmarked',
    label: 'UNMARKED',
    background: Color(0xFFE2E3E5),
    foreground: Color(0xFF3A3D42),
    icon: Icons.shield_outlined,
  );

  /// Built-in default used when a deployment configures no classifications:
  /// a single neutral [fallbackLevel].
  static final ClassificationTheme fallback = ClassificationTheme(
    levels: const [fallbackLevel],
    defaultId: fallbackLevel.id,
  );
}
