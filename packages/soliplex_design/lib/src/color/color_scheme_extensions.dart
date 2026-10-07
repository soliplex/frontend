import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/colors.dart';

/// Semantic status colors resolved from the active Soliplex theme.
///
/// These read the brand's `SoliplexColors` tokens, so a whitelabel theme can
/// recolor them. Outside a Soliplex-themed subtree they fall back to the
/// default palette for the current brightness.
extension SymbolicColors on BuildContext {
  SoliplexColors get _statusColors {
    final theme = SoliplexTheme.maybeOf(this);
    if (theme != null) return theme.colors;
    return Theme.of(this).brightness == Brightness.dark
        ? darkSoliplexColors
        : lightSoliplexColors;
  }

  Color get danger => _statusColors.danger;
  Color get success => _statusColors.success;
  Color get warning => _statusColors.warning;
  Color get info => _statusColors.info;

  /// The warning colour's container surface, and the on-colour drawn on
  /// it.
  ///
  /// These read the same palette as the accessors above; they exist so a
  /// caller wanting a warning *surface* — a banner, say — does not have
  /// to reach through `SoliplexTheme.of(context)`, which throws outright
  /// when no Soliplex theme is installed. Both fall back to the default
  /// palette in that case, as the foreground colours do.
  Color get warningContainer => _statusColors.warningContainer;
  Color get onWarningContainer => _statusColors.onWarningContainer;
}
