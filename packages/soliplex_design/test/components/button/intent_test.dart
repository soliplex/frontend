import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('filledIntentColors', () {
    test('primary maps to (primary, onPrimary)', () {
      final scheme = soliplexLightTheme().colorScheme;
      final pair = filledIntentColors(ButtonIntent.primary, scheme);
      expect(pair.background, scheme.primary);
      expect(pair.foreground, scheme.onPrimary);
    });

    test('danger maps to (error, onError)', () {
      final scheme = soliplexLightTheme().colorScheme;
      final pair = filledIntentColors(ButtonIntent.danger, scheme);
      expect(pair.background, scheme.error);
      expect(pair.foreground, scheme.onError);
    });

    test('danger pulls colours from the active scheme (dark)', () {
      final scheme = soliplexDarkTheme().colorScheme;
      final pair = filledIntentColors(ButtonIntent.danger, scheme);
      expect(pair.background, scheme.error);
      expect(pair.foreground, scheme.onError);
    });
  });

  group('outlinedOrTextIntentForeground', () {
    test('primary maps to scheme.primary', () {
      final scheme = soliplexLightTheme().colorScheme;
      expect(
        outlinedOrTextIntentForeground(ButtonIntent.primary, scheme),
        scheme.primary,
      );
    });

    test('danger maps to scheme.error', () {
      final scheme = soliplexLightTheme().colorScheme;
      expect(
        outlinedOrTextIntentForeground(ButtonIntent.danger, scheme),
        scheme.error,
      );
    });
  });
}
