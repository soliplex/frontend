import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('BrandShape', () {
    test("rounded() carries today's radii", () {
      const shape = BrandShape.rounded();
      expect(shape.sm, 6);
      expect(shape.md, 12);
      expect(shape.lg, 16);
      expect(shape.xl, 24);
    });

    test('square() zeroes every radius', () {
      const shape = BrandShape.square();
      expect(shape.sm, 0);
      expect(shape.md, 0);
      expect(shape.lg, 0);
      expect(shape.xl, 0);
    });

    test('custom() defaults to rounded, overriding only the named step', () {
      const shape = BrandShape.custom(sm: 2);
      expect(shape.sm, 2);
      expect(shape.md, 12);
      expect(shape.lg, 16);
      expect(shape.xl, 24);
    });

    test('equality and copyWith', () {
      const a = BrandShape.rounded();
      expect(a, const BrandShape.custom());
      expect(a, isNot(const BrandShape.square()));
      expect(a.copyWith(md: 20).md, 20);
      expect(a.copyWith(md: 20).sm, 6);
    });

    test('custom() asserts radii are non-negative', () {
      // Via copyWith so the const constructor's assert fires at call time
      // rather than being folded at compile time.
      expect(
        () => const BrandShape.rounded().copyWith(sm: -1),
        throwsAssertionError,
      );
    });
  });

  group('TypeScaleOverride', () {
    test('holds the four primitive deltas', () {
      const o = TypeScaleOverride(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.5,
      );
      expect(o.fontSize, 18);
      expect(o.fontWeight, FontWeight.w600);
      expect(o.height, 1.4);
      expect(o.letterSpacing, 0.5);
    });

    test('defaults every delta to null', () {
      const o = TypeScaleOverride();
      expect(o.fontSize, isNull);
      expect(o.fontWeight, isNull);
      expect(o.height, isNull);
      expect(o.letterSpacing, isNull);
    });

    test('equality', () {
      expect(
        const TypeScaleOverride(fontSize: 18),
        const TypeScaleOverride(fontSize: 18),
      );
      expect(
        const TypeScaleOverride(fontSize: 18),
        isNot(const TypeScaleOverride(fontSize: 20)),
      );
    });

    test('asserts non-negative fontSize and height', () {
      // A runtime value so the call can't be const-folded — a const invocation
      // with a failing assert is a compile error, not the throw we want.
      final negative = double.parse('-1');
      expect(() => TypeScaleOverride(fontSize: negative), throwsAssertionError);
      expect(() => TypeScaleOverride(height: negative), throwsAssertionError);
    });
  });

  group('BrandTypography', () {
    test('defaults to Material families and an empty fallback chain', () {
      const t = BrandTypography();
      expect(t.bodyFamily, isNull);
      expect(t.displayFamily, isNull);
      expect(t.codeFamily, isNull);
      expect(t.fallbacks, isEmpty);
      expect(t.bodyMedium, isNull);
    });

    test('copyWith replaces a single family', () {
      const t = BrandTypography(bodyFamily: 'Inter');
      final next = t.copyWith(displayFamily: 'Fraunces');
      expect(next.bodyFamily, 'Inter');
      expect(next.displayFamily, 'Fraunces');
    });

    test('equality compares the fallback list by value', () {
      expect(
        const BrandTypography(fallbacks: ['Roboto']),
        const BrandTypography(fallbacks: ['Roboto']),
      );
      expect(
        const BrandTypography(fallbacks: ['Roboto']),
        isNot(const BrandTypography(fallbacks: ['Arial'])),
      );
    });
  });

  group('BrandColorScheme', () {
    test('fromAccent sets primary and leaves onPrimary for the lowering layer',
        () {
      final c = BrandColorScheme.fromAccent(
        const Color(0xFF112233),
        brightness: Brightness.light,
      );
      expect(c.primary, const Color(0xFF112233));
      // onPrimary is unset so lowering derives (and can tint) it per accent.
      expect(c.onPrimary, isNull);
      // Every non-primary role stays the neutral light base.
      expect(c.background, const Color(0xFFFFFFFF));
      expect(c.secondary, const Color(0xFFF3F3FA));
      expect(c.foreground, const Color(0xFF0A0A0A));
    });

    test('fromAccent uses the dark neutral base for dark brightness', () {
      final c = BrandColorScheme.fromAccent(
        const Color(0xFF112233),
        brightness: Brightness.dark,
      );
      expect(c.background, const Color(0xFF111111));
      expect(c.foreground, const Color(0xFFFAFAFA));
    });

    test('copyWith and equality', () {
      const c = BrandColorScheme(
        primary: Color(0xFF101010),
        secondary: Color(0xFF202020),
        background: Color(0xFF303030),
        foreground: Color(0xFF404040),
        muted: Color(0xFF505050),
        mutedForeground: Color(0xFF606060),
        border: Color(0xFF707070),
      );
      expect(c, c.copyWith());
      expect(
        c.copyWith(primary: const Color(0xFF000000)).primary,
        const Color(0xFF000000),
      );
      expect(
        c.copyWith(danger: const Color(0xFF00FF00)).danger,
        const Color(0xFF00FF00),
      );
      expect(c, isNot(c.copyWith(primary: const Color(0xFF000000))));
    });

    test('each new optional role participates in equality', () {
      const base = BrandColorScheme(
        primary: Color(0xFF101010),
        secondary: Color(0xFF202020),
        background: Color(0xFF303030),
        foreground: Color(0xFF404040),
        muted: Color(0xFF505050),
        mutedForeground: Color(0xFF606060),
        border: Color(0xFF707070),
      );
      // The seven new roles were wired into `==`/`hashCode` by hand; a field
      // left out would let two schemes that differ only in it compare equal.
      final variants = <BrandColorScheme>[
        base.copyWith(error: const Color(0xFF111111)),
        base.copyWith(onError: const Color(0xFF111111)),
        base.copyWith(errorContainer: const Color(0xFF111111)),
        base.copyWith(onErrorContainer: const Color(0xFF111111)),
        base.copyWith(successContainer: const Color(0xFF111111)),
        base.copyWith(onSuccessContainer: const Color(0xFF111111)),
        base.copyWith(link: const Color(0xFF111111)),
      ];
      for (final v in variants) {
        expect(v, isNot(base));
      }
    });
  });

  group('BrandTheme.soliplex', () {
    test("pins the light palette to today's literals", () {
      final light = const BrandTheme.soliplex().light;
      expect(light.primary, const Color(0xFF030213));
      expect(light.secondary, const Color(0xFFF3F3FA));
      expect(light.background, const Color(0xFFFFFFFF));
      expect(light.foreground, const Color(0xFF0A0A0A));
      expect(light.muted, const Color(0xFFECECF0));
      expect(light.mutedForeground, const Color(0xFF595968));
      expect(light.border, const Color(0x1A000000));
      expect(light.tertiary, const Color(0xFF6B7280));
      expect(light.onPrimary, const Color(0xFFFFFFFF));
    });

    test("pins the dark palette to today's literals", () {
      final dark = const BrandTheme.soliplex().dark;
      expect(dark.primary, const Color(0xFFFAFAFA));
      expect(dark.background, const Color(0xFF111111));
      expect(dark.foreground, const Color(0xFFFAFAFA));
      expect(dark.onPrimary, const Color(0xFF222222));
      expect(dark.tertiary, const Color(0xFF9CA3AF));
    });

    test('leaves status colors unset so the lowering layer supplies defaults',
        () {
      const theme = BrandTheme.soliplex();
      expect(theme.light.danger, isNull);
      expect(theme.light.success, isNull);
      expect(theme.light.warning, isNull);
      expect(theme.light.info, isNull);
    });

    test('defaults typography and shape to the shared Soliplex values', () {
      const theme = BrandTheme.soliplex();
      expect(theme.typography, const BrandTypography());
      expect(theme.shape, const BrandShape.rounded());
    });

    test('is const-constructible and equal across instances', () {
      expect(const BrandTheme.soliplex(), const BrandTheme.soliplex());
    });
  });

  group('BrandTheme.fromSeed', () {
    test('drives both brightness primaries from one seed', () {
      final theme = BrandTheme.fromSeed(const Color(0xFF112233));
      expect(theme.light.primary, const Color(0xFF112233));
      expect(theme.dark.primary, const Color(0xFF112233));
      // onPrimary is derived (and tintable) at lowering, so unset here.
      expect(theme.light.onPrimary, isNull);
      // Neutral bases still differ by brightness.
      expect(theme.light.background, const Color(0xFFFFFFFF));
      expect(theme.dark.background, const Color(0xFF111111));
    });

    test('defaults typography and shape, and accepts overrides', () {
      final plain = BrandTheme.fromSeed(const Color(0xFF112233));
      expect(plain.typography, const BrandTypography());
      expect(plain.shape, const BrandShape.rounded());

      final custom = BrandTheme.fromSeed(
        const Color(0xFF112233),
        typography: const BrandTypography(bodyFamily: 'Inter'),
        shape: const BrandShape.square(),
      );
      expect(custom.typography.bodyFamily, 'Inter');
      expect(custom.shape, const BrandShape.square());
    });
  });

  group('BrandTheme.fromAccents', () {
    test('drives each brightness primary from its own accent', () {
      final theme = BrandTheme.fromAccents(
        light: const Color(0xFF112233),
        dark: const Color(0xFFEE9988),
      );
      expect(theme.light.primary, const Color(0xFF112233));
      expect(theme.dark.primary, const Color(0xFFEE9988));
    });
  });

  group('BrandTheme equality and copyWith', () {
    test('value equality', () {
      expect(
        const BrandTheme.soliplex(),
        isNot(BrandTheme.fromSeed(const Color(0xFFFF0000))),
      );
    });

    test('copyWith swaps a single facet', () {
      const base = BrandTheme.soliplex();
      final next = base.copyWith(shape: const BrandShape.square());
      expect(next.shape, const BrandShape.square());
      expect(next.light, base.light);
    });

    test('tint participates in equality and copyWith', () {
      const base = BrandTheme.soliplex();
      expect(base.tint, const BrandTint());
      const tint = BrandTint(source: TintSource.surface, strength: 0.1);
      final tinted = base.copyWith(tint: tint);
      expect(tinted.tint, tint);
      expect(tinted, isNot(base));
    });

    test('a sourceless tint normalizes strength so no-ops compare equal', () {
      const a = BrandTint(strength: 0.5);
      expect(a.source, TintSource.none);
      expect(a.strength, 0); // strength is pinned to 0 when there is no source
      expect(a, const BrandTint());
    });
  });
}
