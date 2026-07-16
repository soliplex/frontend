import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  group('ShellConfig.fromModules theme-extension guard', () {
    test('throws when lightTheme lacks the SoliplexTheme extension', () {
      expect(
        ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: ThemeData(), // bare, no SoliplexTheme extension
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('succeeds with a buildSoliplexThemeData theme', () async {
      final theme = buildSoliplexThemeData(
          colors: lightSoliplexColors, brightness: Brightness.light);
      final config = await ShellConfig.fromModules(
        modules: const [],
        appName: 'Test',
        lightTheme: theme,
      );
      expect(config.lightTheme, same(theme));
    });
  });
}
