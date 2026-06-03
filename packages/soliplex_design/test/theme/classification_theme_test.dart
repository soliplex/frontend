import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

ClassificationTheme _theme() => ClassificationTheme(
      defaultId: 'low',
      levels: const [
        ClassificationLevel(
          id: 'low',
          label: 'LOW',
          background: Color(0xFF111111),
          foreground: Color(0xFFFFFFFF),
        ),
        ClassificationLevel(
          id: 'high',
          label: 'HIGH',
          background: Color(0xFF222222),
          foreground: Color(0xFFEEEEEE),
          icon: Icons.lock,
        ),
      ],
    );

/// Pumps a minimal app and hands back a [BuildContext]. [theme] `null` →
/// the Material default (no `ClassificationTheme` extension registered).
Future<BuildContext> _context(WidgetTester tester, {ThemeData? theme}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('resolve', () {
    testWidgets('known id returns its level', (tester) async {
      final ctx = await _context(tester);
      final level = _theme().resolve(ctx, 'high');
      expect(level.id, 'high');
      expect(level.label, 'HIGH');
    });

    testWidgets('null returns the default level', (tester) async {
      final ctx = await _context(tester);
      expect(_theme().resolve(ctx, null).id, 'low');
    });

    testWidgets('unknown id returns a fail-loud alarm level', (tester) async {
      final ctx = await _context(tester);
      final scheme = Theme.of(ctx).colorScheme;
      final level = _theme().resolve(ctx, 'mystery');
      expect(level.label, contains('mystery'));
      expect(level.background, scheme.errorContainer);
      expect(level.foreground, scheme.onErrorContainer);
    });
  });

  group('of', () {
    testWidgets('bare ThemeData returns the fallback, no throw',
        (tester) async {
      final ctx = await _context(tester);
      final resolved = ClassificationTheme.of(ctx);
      expect(resolved, same(ClassificationTheme.fallback));
      expect(
        resolved.resolve(ctx, null),
        same(ClassificationTheme.fallbackLevel),
      );
    });
  });

  group('constructor asserts', () {
    test('duplicate ids throw', () {
      expect(
        () => ClassificationTheme(
          defaultId: 'a',
          levels: const [
            ClassificationLevel(
              id: 'a',
              label: 'A',
              background: Color(0xFF000000),
              foreground: Color(0xFFFFFFFF),
            ),
            ClassificationLevel(
              id: 'a',
              label: 'A2',
              background: Color(0xFF000000),
              foreground: Color(0xFFFFFFFF),
            ),
          ],
        ),
        throwsAssertionError,
      );
    });

    test('defaultId not in levels throws', () {
      expect(
        () => ClassificationTheme(
          defaultId: 'missing',
          levels: const [
            ClassificationLevel(
              id: 'a',
              label: 'A',
              background: Color(0xFF000000),
              foreground: Color(0xFFFFFFFF),
            ),
          ],
        ),
        throwsAssertionError,
      );
    });

    test('empty levels throw', () {
      expect(
        () => ClassificationTheme(defaultId: 'a', levels: const []),
        throwsAssertionError,
      );
    });
  });

  group('highestOf', () {
    testWidgets('picks the most restrictive by list position', (tester) async {
      final ctx = await _context(tester);
      expect(_theme().highestOf(ctx, ['low', 'high', 'low']).id, 'high');
    });

    testWidgets('empty returns the default level', (tester) async {
      final ctx = await _context(tester);
      expect(_theme().highestOf(ctx, const []).id, 'low');
    });

    testWidgets('any unknown id yields the alarm level', (tester) async {
      final ctx = await _context(tester);
      final scheme = Theme.of(ctx).colorScheme;
      final level = _theme().highestOf(ctx, ['high', 'ghost']);
      expect(level.background, scheme.errorContainer);
      expect(level.label, contains('ghost'));
    });

    testWidgets('null entries count as the default', (tester) async {
      final ctx = await _context(tester);
      expect(_theme().highestOf(ctx, [null, 'low']).id, 'low');
    });
  });

  group('isMixed', () {
    test('distinct ids are mixed', () {
      expect(_theme().isMixed(['low', 'high']), isTrue);
    });

    test('a single distinct id is not mixed', () {
      expect(_theme().isMixed(['low', 'low']), isFalse);
    });

    test('nulls resolve to the default before comparing', () {
      expect(_theme().isMixed([null, 'low']), isFalse);
      expect(_theme().isMixed([null, 'high']), isTrue);
    });
  });
}
