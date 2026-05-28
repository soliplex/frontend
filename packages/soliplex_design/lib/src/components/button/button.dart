import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/button/intent.dart';
import 'package:soliplex_design/src/components/button/loading_indicator.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// Soliplex's branded button — a thin opinionated layer over Material's
/// [FilledButton] / [OutlinedButton] / [TextButton].
///
/// Three named constructors pick the *visual shape*; [ButtonIntent] picks
/// the *semantic role*. Together they replace four scattered patterns in
/// the app:
///
/// 1. Plain Material buttons + `styleFrom(foregroundColor:
///    colorScheme.error)` for destructive actions.
/// 2. Compact text buttons with hand-rolled `padding` and
///    `visualDensity: compact`.
/// 3. Buttons that need an async loading state (previously absent).
/// 4. `*.icon` constructors duplicated across each shape.
///
/// The widget delegates rendering to the underlying Material button so it
/// always picks up [ThemeData] overrides; we only intervene where the
/// [intent], [isLoading], [isCompact], or [icon] axes require it.
class SoliplexButton extends StatelessWidget {
  /// A filled button — the highest visual weight. Use for the single
  /// confirming action in a view ("Save", "Sign in").
  const SoliplexButton.filled({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.intent = ButtonIntent.primary,
    this.isLoading = false,
  })  : _shape = _ButtonShape.filled,
        isCompact = false;

  /// An outlined button — medium visual weight. Use for secondary
  /// actions ("Cancel", "Back").
  const SoliplexButton.outlined({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.intent = ButtonIntent.primary,
    this.isLoading = false,
  })  : _shape = _ButtonShape.outlined,
        isCompact = false;

  /// A text button — lowest visual weight. Use for tertiary actions
  /// inside dense surfaces (sidebars, list rows) and dialog dismissals.
  ///
  /// Pass [isCompact] to shrink horizontal padding to [SoliplexSpacing.s2]
  /// and switch to [VisualDensity.compact] — the canonical "sidebar link"
  /// pattern.
  const SoliplexButton.text({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.intent = ButtonIntent.primary,
    this.isLoading = false,
    this.isCompact = false,
  }) : _shape = _ButtonShape.text;

  /// Fired on tap. While [isLoading] is true, taps are ignored even if
  /// this is non-null.
  final VoidCallback? onPressed;

  /// The label widget (typically a [Text]). When [isLoading] is true the
  /// label is rendered at zero opacity so the button's measured width is
  /// stable, and a spinner sits centered over it.
  final Widget child;

  /// Optional icon. Sits before the label by default; pass
  /// [iconAlignment] to move it after. If [isLoading] is true the icon
  /// slot becomes the spinner and the label fades.
  final Widget? icon;

  /// Which side of the label the [icon] sits on. Ignored when [icon] is
  /// null. Mirrors Material's `IconAlignment` — use [IconAlignment.end]
  /// for trailing affordances ("Next →", "Go to Lobby →").
  final IconAlignment iconAlignment;

  /// Semantic role — defaults to [ButtonIntent.primary]. [ButtonIntent.danger]
  /// swaps to the theme's error palette.
  final ButtonIntent intent;

  /// While true, [onPressed] is ignored and a spinner is shown.
  final bool isLoading;

  /// `text`-shape only: shrink horizontal padding and visual density.
  ///
  /// Visual compactness only — the underlying tap target still satisfies
  /// the Material 48 logical-px minimum via [MaterialTapTargetSize.padded].
  final bool isCompact;

  final _ButtonShape _shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = isLoading ? null : onPressed;

    switch (_shape) {
      case _ButtonShape.filled:
        return _buildFilled(scheme, effectiveOnPressed);
      case _ButtonShape.outlined:
        return _buildOutlined(scheme, effectiveOnPressed);
      case _ButtonShape.text:
        return _buildText(scheme, effectiveOnPressed);
    }
  }

  Widget _buildFilled(ColorScheme scheme, VoidCallback? effectiveOnPressed) {
    final colors = filledIntentColors(intent, scheme);
    final style = FilledButton.styleFrom(
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
    );
    final body = _label(colors.foreground);
    if (icon != null) {
      return FilledButton.icon(
        onPressed: effectiveOnPressed,
        style: style,
        iconAlignment: iconAlignment,
        icon: _iconOrSpinner(colors.foreground),
        label: body,
      );
    }
    return FilledButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: body,
    );
  }

  Widget _buildOutlined(ColorScheme scheme, VoidCallback? effectiveOnPressed) {
    final fg = outlinedOrTextIntentForeground(intent, scheme);
    final style = OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: intent == ButtonIntent.danger
          ? BorderSide(color: fg.withValues(alpha: 0.5))
          : null,
    );
    final body = _label(fg);
    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: effectiveOnPressed,
        style: style,
        iconAlignment: iconAlignment,
        icon: _iconOrSpinner(fg),
        label: body,
      );
    }
    return OutlinedButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: body,
    );
  }

  Widget _buildText(ColorScheme scheme, VoidCallback? effectiveOnPressed) {
    final fg = outlinedOrTextIntentForeground(intent, scheme);
    final style = TextButton.styleFrom(
      foregroundColor: fg,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2)
          : null,
      visualDensity: isCompact ? VisualDensity.compact : null,
      minimumSize: isCompact ? Size.zero : null,
    );
    final body = _label(fg);
    if (icon != null) {
      return TextButton.icon(
        onPressed: effectiveOnPressed,
        style: style,
        iconAlignment: iconAlignment,
        icon: _iconOrSpinner(fg),
        label: body,
      );
    }
    return TextButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: body,
    );
  }

  /// The label, possibly stacked under a centered spinner.
  ///
  /// When [icon] is non-null, the icon slot carries the spinner and the
  /// label only fades — so we don't need a Stack here. When [icon] is
  /// null, we Stack the spinner over the label.
  Widget _label(Color foregroundColor) {
    if (!isLoading) return child;
    if (icon != null) {
      return Opacity(opacity: 0, child: child);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0, child: child),
        ButtonLoadingIndicator(foregroundColor: foregroundColor),
      ],
    );
  }

  /// The leading icon or, in the loading state, the spinner at the same
  /// slot.
  Widget _iconOrSpinner(Color foregroundColor) {
    if (!isLoading) return icon!;
    return ButtonLoadingIndicator(foregroundColor: foregroundColor);
  }
}

enum _ButtonShape { filled, outlined, text }
