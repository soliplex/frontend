import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/src/brand/brand_lowering.dart';
import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/contrast.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/theme/theme.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

class _RecordingResolver implements FontResolver {
  final List<String> requested = [];

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) {
    requested.add(family);
    return ResolvedFont(
      fontFamily: '$family!',
      fontFamilyFallback: fallbacks,
    );
  }
}

void expectSameColors(SoliplexColors a, SoliplexColors b) {
  expect(a.background, b.background, reason: 'background');
  expect(a.foreground, b.foreground, reason: 'foreground');
  expect(a.primary, b.primary, reason: 'primary');
  expect(a.onPrimary, b.onPrimary, reason: 'onPrimary');
  expect(a.primaryContainer, b.primaryContainer, reason: 'primaryContainer');
  expect(
    a.onPrimaryContainer,
    b.onPrimaryContainer,
    reason: 'onPrimaryContainer',
  );
  expect(a.secondary, b.secondary, reason: 'secondary');
  expect(a.onSecondary, b.onSecondary, reason: 'onSecondary');
  expect(a.tertiary, b.tertiary, reason: 'tertiary');
  expect(a.onTertiary, b.onTertiary, reason: 'onTertiary');
  expect(a.tertiaryContainer, b.tertiaryContainer, reason: 'tertiaryContainer');
  expect(
    a.onTertiaryContainer,
    b.onTertiaryContainer,
    reason: 'onTertiaryContainer',
  );
  expect(a.accent, b.accent, reason: 'accent');
  expect(a.onAccent, b.onAccent, reason: 'onAccent');
  expect(a.muted, b.muted, reason: 'muted');
  expect(a.mutedForeground, b.mutedForeground, reason: 'mutedForeground');
  expect(a.destructive, b.destructive, reason: 'destructive');
  expect(a.onDestructive, b.onDestructive, reason: 'onDestructive');
  expect(a.errorContainer, b.errorContainer, reason: 'errorContainer');
  expect(a.onErrorContainer, b.onErrorContainer, reason: 'onErrorContainer');
  expect(a.successContainer, b.successContainer, reason: 'successContainer');
  expect(
    a.onSuccessContainer,
    b.onSuccessContainer,
    reason: 'onSuccessContainer',
  );
  expect(a.danger, b.danger, reason: 'danger');
  expect(a.success, b.success, reason: 'success');
  expect(a.warning, b.warning, reason: 'warning');
  expect(a.info, b.info, reason: 'info');
  expect(a.border, b.border, reason: 'border');
  expect(a.outline, b.outline, reason: 'outline');
  expect(a.outlineVariant, b.outlineVariant, reason: 'outlineVariant');
  expect(a.inputBackground, b.inputBackground, reason: 'inputBackground');
  expect(a.hintText, b.hintText, reason: 'hintText');
  expect(
    a.surfaceContainerLowest,
    b.surfaceContainerLowest,
    reason: 'surfaceContainerLowest',
  );
  expect(
    a.surfaceContainerLow,
    b.surfaceContainerLow,
    reason: 'surfaceContainerLow',
  );
  expect(
    a.surfaceContainerHigh,
    b.surfaceContainerHigh,
    reason: 'surfaceContainerHigh',
  );
  expect(
    a.surfaceContainerHighest,
    b.surfaceContainerHighest,
    reason: 'surfaceContainerHighest',
  );
  expect(a.inversePrimary, b.inversePrimary, reason: 'inversePrimary');
  expect(a.link, b.link, reason: 'link');
}

SoliplexColors loweredColors(BrandTheme theme, Brightness brightness) =>
    lowerBrandTheme(theme, brightness).extension<SoliplexTheme>()!.colors;

void main() {
  late MemorySink logs;
  setUp(() {
    logs = MemorySink();
    LogManager.instance.addSink(logs);
  });
  tearDown(LogManager.instance.reset);

  Iterable<LogRecord> contrastWarnings() =>
      logs.records.where((r) => r.level == LogLevel.warning);
  Iterable<LogRecord> roleWarnings(String role) =>
      contrastWarnings().where((r) => r.attributes['role'] == role);

  group('lowerBrandTheme defaults are byte-identical to today', () {
    test('light palette', () {
      expectSameColors(
        loweredColors(const BrandTheme.soliplex(), Brightness.light),
        lightSoliplexColors,
      );
    });

    test('dark palette', () {
      expectSameColors(
        loweredColors(const BrandTheme.soliplex(), Brightness.dark),
        darkSoliplexColors,
      );
    });

    test('replicates the integer-alpha badge blend', () {
      final lowered =
          lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light);
      expect(
        lowered.extension<SoliplexTheme>()!.badgeTheme.background,
        soliplexLightTheme().extension<SoliplexTheme>()!.badgeTheme.background,
      );
    });
  });

  group('lowerBrandTheme maps the façade onto slots', () {
    test('a seed drives primary with a contrasting onPrimary', () {
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF112233)),
        Brightness.light,
      );
      expect(colors.primary, const Color(0xFF112233));
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
    });

    test('a mid-tone seed still derives an AA-readable onPrimary', () {
      // A mid-luminance seed is the case where the softer #0A0A0A foreground
      // bottoms out below AA; fromAccent must pick a pure black/white tone.
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF777777)),
        Brightness.light,
      );
      expect(
        contrastRatio(colors.primary, colors.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('an unspecified onColor gets a WCAG-readable foreground', () {
      const handBuilt = BrandColorScheme(
        primary: Color(0xFF808080),
        secondary: Color(0xFF808080),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF0A0A0A),
        muted: Color(0xFFECECF0),
        mutedForeground: Color(0xFF595968),
        border: Color(0x1A000000),
      );
      final theme = BrandTheme(
        light: handBuilt,
        dark: const BrandTheme.soliplex().dark,
      );
      final colors = loweredColors(theme, Brightness.light);

      expect(
        contrastRatio(colors.primary, colors.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('unspecified status colors fall back to the neutral base', () {
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF112233)),
        Brightness.light,
      );
      expect(colors.danger, lightSoliplexColors.danger);
      expect(colors.info, lightSoliplexColors.info);
    });
  });

  group('lowerBrandTheme threads shape and typography', () {
    test('shape drives the radii', () {
      final theme = lowerBrandTheme(
        const BrandTheme(
          light: BrandColorScheme(
            primary: Color(0xFF030213),
            secondary: Color(0xFFF3F3FA),
            background: Color(0xFFFFFFFF),
            foreground: Color(0xFF0A0A0A),
            muted: Color(0xFFECECF0),
            mutedForeground: Color(0xFF595968),
            border: Color(0x1A000000),
            onPrimary: Color(0xFFFFFFFF),
            onSecondary: Color(0xFF030213),
          ),
          dark: BrandColorScheme(
            primary: Color(0xFFFAFAFA),
            secondary: Color(0xFF2A2A2A),
            background: Color(0xFF111111),
            foreground: Color(0xFFFAFAFA),
            muted: Color(0xFF444444),
            mutedForeground: Color(0xFFAAAAAA),
            border: Color(0xFF2A2A2A),
            onPrimary: Color(0xFF222222),
            onSecondary: Color(0xFFFFFFFF),
          ),
          shape: BrandShape.square(),
        ),
        Brightness.light,
      );
      expect(theme.extension<SoliplexTheme>()!.radii.md, 0);
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(0),
      );
    });

    test('body and display families flow into the text theme', () {
      final theme = lowerBrandTheme(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(bodyFamily: 'Inter'),
        ),
        Brightness.light,
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      // Display falls back to the body family.
      expect(theme.textTheme.headlineMedium!.fontFamily, 'Inter');
    });

    test('codeFamily becomes the monospace token', () {
      final theme = lowerBrandTheme(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(codeFamily: 'Brandospace'),
        ),
        Brightness.light,
      );
      expect(
        theme.extension<SoliplexTheme>()!.monospace.family,
        'Brandospace',
      );
    });

    test('families resolve through the injected FontResolver', () {
      final resolver = _RecordingResolver();
      final theme = lowerBrandTheme(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(bodyFamily: 'Inter'),
        ),
        Brightness.light,
        fontResolver: resolver,
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter!');
      expect(resolver.requested, contains('Inter'));
    });
  });

  group('a full custom brand lowers across every axis', () {
    test('accents, families, and shape all reach the ThemeData', () {
      final resolver = _RecordingResolver();
      final theme = lowerBrandTheme(
        BrandTheme.fromAccents(
          light: const Color(0xFF0066CC),
          dark: const Color(0xFF99CCFF),
          typography: const BrandTypography(
            bodyFamily: 'Inter',
            displayFamily: 'Fraunces',
          ),
          shape: const BrandShape.square(),
        ),
        Brightness.light,
        fontResolver: resolver,
      );

      expect(theme.colorScheme.primary, const Color(0xFF0066CC));
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter!');
      expect(theme.textTheme.headlineMedium!.fontFamily, 'Fraunces!');
      expect(theme.extension<SoliplexTheme>()!.radii.md, 0);
    });
  });

  group('lowerBrandTheme contrast warning', () {
    test('warns but keeps a sub-threshold on-color pair verbatim', () {
      final bad = const BrandTheme.soliplex().light.copyWith(
            primary: const Color(0xFFFFFFFF),
            onPrimary: const Color(0xFFFFFFFF),
          );
      final colors = loweredColors(
        BrandTheme(light: bad, dark: const BrandTheme.soliplex().dark),
        Brightness.light,
      );
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(roleWarnings('onPrimary'), hasLength(1));
    });

    test('the default theme produces no contrast warnings', () {
      loweredColors(const BrandTheme.soliplex(), Brightness.light);
      loweredColors(const BrandTheme.soliplex(), Brightness.dark);
      expect(contrastWarnings(), isEmpty);
    });

    test('an auto-derived on-color never warns', () {
      loweredColors(
        BrandTheme.fromSeed(const Color(0xFF0066CC)),
        Brightness.light,
      );
      expect(contrastWarnings(), isEmpty);
    });
  });

  group('lowerBrandTheme lowers the error / status-surface / link roles', () {
    BrandTheme brandWith(BrandColorScheme Function(BrandColorScheme) edit) =>
        BrandTheme(
          light: edit(const BrandTheme.soliplex().light),
          dark: const BrandTheme.soliplex().dark,
        );

    test('error and onError drive the destructive slot', () {
      final colors = loweredColors(
        brandWith(
          (b) => b.copyWith(
            error: const Color(0xFF7A0010),
            onError: const Color(0xFFFFEEEE),
          ),
        ),
        Brightness.light,
      );
      expect(colors.destructive, const Color(0xFF7A0010));
      expect(colors.onDestructive, const Color(0xFFFFEEEE));
    });

    test('link drives the link slot', () {
      final colors = loweredColors(
        brandWith((b) => b.copyWith(link: const Color(0xFF7C3AED))),
        Brightness.light,
      );
      expect(colors.link, const Color(0xFF7C3AED));
    });

    test('error and success containers drive their slots', () {
      final colors = loweredColors(
        brandWith(
          (b) => b.copyWith(
            errorContainer: const Color(0xFF330007),
            successContainer: const Color(0xFF062E12),
          ),
        ),
        Brightness.light,
      );
      expect(colors.errorContainer, const Color(0xFF330007));
      expect(colors.successContainer, const Color(0xFF062E12));
    });

    test('explicit container on-colors survive lowering', () {
      // Off-white on-colors, distinct from what readableOn would derive for
      // these dark surfaces (pure white) — proves the explicit on-color wins
      // and that each container's on-color is wired to its own field.
      final colors = loweredColors(
        brandWith(
          (b) => b.copyWith(
            errorContainer: const Color(0xFF330007),
            onErrorContainer: const Color(0xFFFFE9EC),
            successContainer: const Color(0xFF062E12),
            onSuccessContainer: const Color(0xFFEAFBF0),
          ),
        ),
        Brightness.light,
      );
      expect(colors.onErrorContainer, const Color(0xFFFFE9EC));
      expect(colors.onSuccessContainer, const Color(0xFFEAFBF0));
    });

    test('an unspecified on-color derives a WCAG-readable foreground', () {
      final colors = loweredColors(
        brandWith(
          (b) => b.copyWith(
            error: const Color(0xFF7A0010),
            errorContainer: const Color(0xFFFDE7EA),
            successContainer: const Color(0xFFE6F6EC),
          ),
        ),
        Brightness.light,
      );
      expect(
        contrastRatio(colors.destructive, colors.onDestructive),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.errorContainer, colors.onErrorContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.successContainer, colors.onSuccessContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('unspecified Group A colors fall back to the neutral base', () {
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF112233)),
        Brightness.light,
      );
      expect(colors.destructive, lightSoliplexColors.destructive);
      expect(colors.onDestructive, lightSoliplexColors.onDestructive);
      expect(colors.link, lightSoliplexColors.link);
      expect(colors.errorContainer, lightSoliplexColors.errorContainer);
      expect(colors.onErrorContainer, lightSoliplexColors.onErrorContainer);
      expect(colors.successContainer, lightSoliplexColors.successContainer);
      expect(colors.onSuccessContainer, lightSoliplexColors.onSuccessContainer);
    });

    test('a custom tertiary lowers and derives an AA on-color', () {
      final colors = loweredColors(
        brandWith((b) => b.copyWith(tertiary: const Color(0xFF2E7D32))),
        Brightness.light,
      );
      expect(colors.tertiary, const Color(0xFF2E7D32));
      expect(
        contrastRatio(colors.tertiary, colors.onTertiary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('custom error / container roles lower in the dark palette', () {
      final colors = loweredColors(
        BrandTheme(
          light: const BrandTheme.soliplex().light,
          dark: const BrandTheme.soliplex().dark.copyWith(
                error: const Color(0xFFCF6679),
                errorContainer: const Color(0xFF3D1A1A),
              ),
        ),
        Brightness.dark,
      );
      expect(colors.destructive, const Color(0xFFCF6679));
      expect(colors.errorContainer, const Color(0xFF3D1A1A));
      expect(
        contrastRatio(colors.errorContainer, colors.onErrorContainer),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('lowerBrandTheme contrast warning scopes link and covers foreground',
      () {
    BrandTheme badLight(BrandColorScheme Function(BrandColorScheme) edit) =>
        BrandTheme(
          light: edit(const BrandTheme.soliplex().light),
          dark: const BrandTheme.soliplex().dark,
        );

    test('warns on an illegible link against the background', () {
      loweredColors(
        badLight((b) => b.copyWith(link: const Color(0xFFFFFFFF))),
        Brightness.light,
      );
      expect(roleWarnings('link'), hasLength(1));
    });

    test('does not warn on an unset link, even with an off-white background',
        () {
      // A fork lightens only the background; the *default* link would be
      // sub-AA against it, but link is not a role this fork set, so it is not
      // the fork's responsibility and must not warn.
      loweredColors(
        badLight((b) => b.copyWith(background: const Color(0xFFEEEEEE))),
        Brightness.light,
      );
      expect(roleWarnings('link'), isEmpty);
    });

    test('warns on a sub-threshold foreground / background pair', () {
      loweredColors(
        badLight(
          (b) => b.copyWith(
            background: const Color(0xFFFFFFFF),
            foreground: const Color(0xFFEEEEEE),
          ),
        ),
        Brightness.light,
      );
      expect(roleWarnings('foreground'), hasLength(1));
    });
  });
}
