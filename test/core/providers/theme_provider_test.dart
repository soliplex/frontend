import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/providers/theme_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetPreloadedThemeMode();
  });

  group('themeModeProvider', () {
    test('default value is ThemeMode.system', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('toggle from system + light brightness sets dark mode', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).toggle(Brightness.light);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('toggle from system + dark brightness sets light mode', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).toggle(Brightness.dark);

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('toggle from light sets dark', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).toggle(Brightness.light);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      await container.read(themeModeProvider.notifier).toggle(Brightness.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('toggle from dark sets light', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // First go from system to dark
      await container.read(themeModeProvider.notifier).toggle(Brightness.light);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      // Then dark → light (system brightness ignored when not in system mode)
      await container.read(themeModeProvider.notifier).toggle(Brightness.dark);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('toggle persists value to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).toggle(Brightness.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });
  });

  group('initializeTheme', () {
    test('loads dark mode from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

      await initializeTheme();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('loads light mode from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

      await initializeTheme();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('loads system mode from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'system'});

      await initializeTheme();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('falls back to system when no value stored', () async {
      SharedPreferences.setMockInitialValues({});

      await initializeTheme();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('falls back to system when stored value is invalid', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'banana'});

      await initializeTheme();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
