import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('monospaceFontFamily', () {
    test('Apple platforms use SF Mono with Menlo fallback', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final mono = monospaceFontFamily(p);
        expect(mono.family, 'SF Mono');
        expect(mono.fallback, const ['Menlo', 'monospace']);
      }
    });

    test('non-Apple platforms use Roboto Mono', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        final mono = monospaceFontFamily(p);
        expect(mono.family, 'Roboto Mono');
        expect(mono.fallback, const ['monospace']);
      }
    });
  });

  group('context.monospace', () {
    testWidgets('reads the monospace family from the theme extension',
        (tester) async {
      const brandMono = (family: 'Brandospace', fallback: ['monospace']);
      final base = soliplexLightTheme();
      final ext =
          base.extension<SoliplexTheme>()!.copyWith(monospace: brandMono);
      final theme = base.copyWith(
        extensions: [
          ...base.extensions.values.where((e) => e is! SoliplexTheme),
          ext,
        ],
      );

      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              style = context.monospace;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(style.fontFamily, 'Brandospace');
      expect(style.fontFamilyFallback, const ['monospace']);
    });

    testWidgets('falls back to the platform family without the extension',
        (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              style = context.monospace;
              return const SizedBox();
            },
          ),
        ),
      );

      final platform = monospaceFontFamily(defaultTargetPlatform);
      expect(style.fontFamily, platform.family);
    });

    testWidgets('monospaceOn applies the family while keeping the base style',
        (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Builder(
            builder: (context) {
              style = context.monospaceOn(
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              );
              return const SizedBox();
            },
          ),
        ),
      );

      final platform = monospaceFontFamily(defaultTargetPlatform);
      expect(style.fontFamily, platform.family);
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w700);
    });
  });
}
