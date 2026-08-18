import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/chip/intent.dart';
import 'package:soliplex_design/src/tokens/swatch.dart';

/// A pill-shaped surface used for tags, filters, and small actions —
/// Soliplex's thin layer over Material's `Chip` family.
///
/// Three flavours via named constructors:
///
/// - `SoliplexChip()` — static **display** chip. Renders a label,
///   optional leading icon, optional `onDeleted` close button. Carries
///   an [intent] for status tinting.
/// - `SoliplexChip.action()` — **tappable** chip. Behaves like a small
///   button; takes [intent] for danger/success/etc. variants.
/// - `SoliplexChip.filter()` — **toggleable** chip. `selected` paints
///   it with the theme's primary tint; intent is not exposed because
///   selection-state already carries semantic meaning.
/// - `SoliplexChip.colored()` — display chip in an **arbitrary colour**,
///   for identities the theme cannot know in advance (thread labels,
///   whose colours users choose). The swatch is quieted into a wash, an
///   outline, and text, so a chosen colour can be neither unreadable nor
///   loud enough to out-shout what it annotates.
class SoliplexChip extends StatelessWidget {
  /// Static label chip. Pass [onDeleted] to add a trailing close button.
  const SoliplexChip({
    required this.label,
    super.key,
    this.icon,
    this.onDeleted,
    this.intent = ChipIntent.neutral,
  })  : _kind = _ChipKind.display,
        _onPressed = null,
        _selected = false,
        _onSelected = null,
        _color = null;

  /// Action chip — tap to fire [onPressed].
  const SoliplexChip.action({
    required this.label,
    required VoidCallback onPressed,
    super.key,
    this.icon,
    this.intent = ChipIntent.neutral,
  })  : _kind = _ChipKind.action,
        _onPressed = onPressed,
        onDeleted = null,
        _selected = false,
        _onSelected = null,
        _color = null;

  /// Filter chip — toggleable, [selected] paints the primary tint.
  const SoliplexChip.filter({
    required this.label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    super.key,
    this.icon,
  })  : _kind = _ChipKind.filter,
        _selected = selected,
        _onSelected = onSelected,
        _onPressed = null,
        onDeleted = null,
        intent = ChipIntent.neutral,
        _color = null;

  /// Display chip carrying an arbitrary [color].
  ///
  /// For identities whose colour is data rather than semantics — a
  /// thread label, say, whose swatch a user picked. The status
  /// [ChipIntent] vocabulary cannot express those: it is a closed set,
  /// and a label is not a status.
  ///
  /// Only the swatch is taken; `swatchTint` derives what is actually
  /// painted. The chip is an outlined wash rather than a solid fill —
  /// a label annotates a thread and must not compete with it — and the
  /// foreground is never supplied by the caller, since an open-ended
  /// colour field otherwise invites white text on pale yellow. Pass
  /// [onDeleted] for a trailing close button, tinted to match.
  const SoliplexChip.colored({
    required this.label,
    required Color color,
    super.key,
    this.icon,
    this.onDeleted,
  })  : _kind = _ChipKind.colored,
        _color = color,
        _onPressed = null,
        _selected = false,
        _onSelected = null,
        intent = ChipIntent.neutral;

  /// The label widget (typically a [Text]).
  final Widget label;

  /// Optional leading icon.
  final Widget? icon;

  /// Trailing close button — display chips only. Tap-to-dismiss flow.
  final VoidCallback? onDeleted;

  /// Status flavour. Filter chips ignore this (selection carries
  /// the semantic instead).
  final ChipIntent intent;

  final _ChipKind _kind;
  final VoidCallback? _onPressed;
  final bool _selected;
  final ValueChanged<bool>? _onSelected;
  final Color? _color;

  @override
  Widget build(BuildContext context) {
    final colors = chipIntentColors(intent, context);
    final labelStyle =
        colors.foreground == null ? null : TextStyle(color: colors.foreground);

    return switch (_kind) {
      _ChipKind.colored => _buildColored(context),
      _ChipKind.display => Chip(
          label: label,
          avatar: _avatar(colors.foreground),
          onDeleted: onDeleted,
          backgroundColor: colors.background,
          labelStyle: labelStyle,
          deleteIconColor: colors.foreground,
        ),
      _ChipKind.action => ActionChip(
          label: label,
          avatar: _avatar(colors.foreground),
          onPressed: _onPressed,
          backgroundColor: colors.background,
          labelStyle: labelStyle,
        ),
      _ChipKind.filter => FilterChip(
          label: label,
          avatar: _avatar(null),
          selected: _selected,
          onSelected: _onSelected,
        ),
    };
  }

  /// The quieted rendering of a data-supplied swatch.
  ///
  /// The border is spelled out rather than left to the theme because
  /// `Chip`'s default side is drawn from the colour scheme, which knows
  /// nothing of this swatch — the outline is the part carrying the
  /// label's identity, so it has to come from the same tint as the fill.
  Widget _buildColored(BuildContext context) {
    final tint = swatchTint(_color!, Theme.of(context).brightness);
    return Chip(
      label: label,
      avatar: _avatar(tint.content),
      onDeleted: onDeleted,
      backgroundColor: tint.fill,
      side: BorderSide(color: tint.outline),
      labelStyle: TextStyle(color: tint.content),
      deleteIconColor: tint.content,
    );
  }

  /// Wraps [icon] in an [IconTheme] tinted to the intent's foreground
  /// so the leading glyph matches the label text. Returns null when no
  /// icon is supplied.
  Widget? _avatar(Color? foregroundColor) {
    if (icon == null) return null;
    return IconTheme.merge(
      data: IconThemeData(color: foregroundColor, size: 16),
      child: icon!,
    );
  }
}

enum _ChipKind { display, action, filter, colored }
