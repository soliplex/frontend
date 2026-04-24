import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/core/providers/theme_provider.dart';
import 'package:soliplex_frontend/src/shared/theme_toggle_button.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetPreloadedThemeMode();
  });

  Widget buildHarness({Brightness platformBrightness = Brightness.light}) {
    return ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(platformBrightness: platformBrightness),
        child: const MaterialApp(
          home: Scaffold(body: ThemeToggleButton()),
        ),
      ),
    );
  }

  group('ThemeToggleButton', () {
    testWidgets('shows dark_mode icon when current effective theme is light',
        (tester) async {
      await tester.pumpWidget(buildHarness());

      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsNothing);
    });

    testWidgets('shows light_mode icon when system brightness is dark',
        (tester) async {
      await tester.pumpWidget(
        buildHarness(platformBrightness: Brightness.dark),
      );

      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsNothing);
    });

    testWidgets('tooltip says "Switch to dark mode" when in light mode',
        (tester) async {
      await tester.pumpWidget(buildHarness());

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Switch to dark mode');
    });

    testWidgets('tooltip says "Switch to light mode" when in dark mode',
        (tester) async {
      await tester.pumpWidget(
        buildHarness(platformBrightness: Brightness.dark),
      );

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Switch to light mode');
    });

    testWidgets('tap toggles theme mode from system+light to dark',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                home: Scaffold(body: ThemeToggleButton()),
              );
            },
          ),
        ),
      );

      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('updates icon after toggle', (tester) async {
      await tester.pumpWidget(buildHarness());

      // Initially shows dark_mode (will switch TO dark)
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Now in dark mode, shows light_mode icon (will switch TO light)
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsNothing);
    });
  });
}
