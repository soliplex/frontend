import 'package:flutter/material.dart';

/// Semantic role of a `SoliplexButton`, decoupled from its visual shape.
///
/// The shape (`filled` / `outlined` / `text`) is chosen by the named
/// constructor; the *intent* says *what kind of action* the button performs.
/// The same shape can express different intents — a destructive `delete`
/// uses a filled button just like a confirming `save`, but with a different
/// palette.
enum ButtonIntent {
  /// Confirming actions ("Save", "Sign in", "Continue"). Uses the
  /// theme's primary palette.
  primary,

  /// Destructive actions ("Delete", "Sign out", "Remove"). Uses the
  /// theme's error palette so the destructive nature is visually obvious.
  danger,
}

/// The `(background, foreground)` colour pair for a filled button at this
/// intent under the given [scheme].
///
/// Pulled into a top-level helper so the same mapping is shared by
/// `SoliplexButton.filled` and by intent tests. The pair is the same shape
/// Material's [FilledButton.styleFrom] expects.
({Color background, Color foreground}) filledIntentColors(
  ButtonIntent intent,
  ColorScheme scheme,
) {
  switch (intent) {
    case ButtonIntent.primary:
      return (background: scheme.primary, foreground: scheme.onPrimary);
    case ButtonIntent.danger:
      return (background: scheme.error, foreground: scheme.onError);
  }
}

/// The single foreground colour for an outlined or text button at this
/// intent. Outlined buttons additionally tint their border with this
/// colour at a reduced opacity (see `SoliplexButton`).
Color outlinedOrTextIntentForeground(
  ButtonIntent intent,
  ColorScheme scheme,
) {
  switch (intent) {
    case ButtonIntent.primary:
      return scheme.primary;
    case ButtonIntent.danger:
      return scheme.error;
  }
}
