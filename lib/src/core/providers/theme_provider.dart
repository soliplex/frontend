import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'theme_mode';

/// Initial theme mode loaded before app starts.
///
/// Set this in main() via [initializeTheme] BEFORE runApp().
ThemeMode? _preloadedThemeMode;

/// Resets the preloaded theme mode for testing.
///
/// This allows tests to run in isolation without state pollution.
@visibleForTesting
void resetPreloadedThemeMode() {
  _preloadedThemeMode = null;
}

/// Loads and caches theme mode from SharedPreferences.
///
/// Call this in main() BEFORE runApp() to ensure the correct theme
/// is available from the first frame (avoids flash of wrong theme).
Future<void> initializeTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final savedValue = prefs.getString(_themeModeKey);

  if (savedValue != null) {
    _preloadedThemeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == savedValue,
      orElse: () => ThemeMode.system,
    );
  }
}

/// Notifier for theme mode state.
///
/// Persists to SharedPreferences for cross-session persistence.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return _preloadedThemeMode ?? ThemeMode.system;
  }

  /// Toggle between light and dark mode.
  ///
  /// If current mode is system, resolves to actual brightness first,
  /// then toggles to the opposite.
  Future<void> toggle(Brightness systemBrightness) async {
    final currentEffective = state == ThemeMode.system
        ? (systemBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light)
        : state;

    final newMode =
        currentEffective == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

    await _setAndPersist(newMode);
  }

  /// Set theme mode and persist to storage.
  Future<void> _setAndPersist(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    state = mode;
  }
}

/// Provider for theme mode state.
///
/// Dependent widgets automatically rebuild when theme mode changes.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
