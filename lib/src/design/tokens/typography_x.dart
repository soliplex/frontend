import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

extension TypographyX on BuildContext {
  /// Monospace using `bodyMedium` as the base. For a different base size use
  /// `SoliplexTheme.withCodeFont(context, base)` directly.
  TextStyle get monospace => SoliplexTheme.withCodeFont(this);
}
