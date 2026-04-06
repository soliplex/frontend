import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_provider.dart';

/// Button that toggles between light and dark theme.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final systemBrightness = MediaQuery.platformBrightnessOf(context);

    // Determine effective brightness for icon selection
    final effectiveBrightness = themeMode == ThemeMode.system
        ? systemBrightness
        : (themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);

    final isDark = effectiveBrightness == Brightness.dark;

    return Semantics(
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: IconButton(
        icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
        tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () {
          ref.read(themeModeProvider.notifier).toggle(systemBrightness);
        },
      ),
    );
  }
}
