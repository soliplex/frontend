import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'route_module.dart';

ThemeData _lightTheme() => buildSoliplexThemeData(
      colors: lightSoliplexColors,
      brightness: Brightness.light,
    );

void main() {
  group('ShellConfig.fromModules theme-extension guard', () {
    test('throws when lightTheme lacks the SoliplexTheme extension', () {
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: ThemeData(), // bare, no SoliplexTheme extension
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when darkTheme lacks the SoliplexTheme extension', () {
      final light = buildSoliplexThemeData(
          colors: lightSoliplexColors, brightness: Brightness.light);
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: light,
          darkTheme: ThemeData(), // bare dark theme, no extension
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShellConfig.fromModules route guard', () {
    test('throws when modules contribute no routes', () {
      expect(
        () => ShellConfig.fromModules(
          modules: const [],
          appName: 'Test',
          lightTheme: _lightTheme(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when initialRoute matches no route', () {
      expect(
        () => ShellConfig.fromModules(
          modules: [
            RouteModule(const ['/a'])
          ],
          appName: 'Test',
          lightTheme: _lightTheme(),
          initialRoute: '/missing',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Initial route'),
          ),
        ),
      );
    });
  });
}
