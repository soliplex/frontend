import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_frontend/src/modules/preferences/preferences_screen.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

Future<void> _pump(WidgetTester tester, BandwidthPreference preference) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: PreferencesScreen(appName: 'Acme', preference: preference),
    ),
  );
  await tester.pumpAndSettle();
}

final _unsaved = find.text(
  "Couldn't save this preference. It applies until the app restarts.",
);

/// Captures this module's error records for the test.
Iterable<LogRecord> Function() _captureErrors() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => sink.records.where(
        (r) =>
            r.level == LogLevel.error &&
            r.loggerName == 'soliplex.bandwidth_preference',
      );
}

Future<SharedPreferences> _unavailable() =>
    Future.error(StateError('prefs unavailable'));

Future<void> _toggle(WidgetTester tester) async {
  await tester.tap(find.text('Low bandwidth mode'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping the switch turns low bandwidth on', (tester) async {
    final preference = BandwidthPreference();
    await tester.runAsync(preference.load);
    await _pump(tester, preference);

    await _toggle(tester);

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(_unsaved, findsNothing);
  });

  testWidgets('an unsaved change shows the banner', (tester) async {
    final errors = _captureErrors();
    await _pump(tester, BandwidthPreference(prefsFactory: _unavailable));

    await _toggle(tester);

    expect(_unsaved, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(errors(), hasLength(1));
  });

  testWidgets('a later successful save clears the banner', (tester) async {
    final errors = _captureErrors();
    var failing = true;
    await _pump(
      tester,
      BandwidthPreference(
        prefsFactory: () =>
            failing ? _unavailable() : SharedPreferences.getInstance(),
      ),
    );
    await _toggle(tester);
    failing = false;

    await _toggle(tester);

    expect(_unsaved, findsNothing);
    expect(errors(), hasLength(1));
  });

  testWidgets('dismissing hides the banner', (tester) async {
    final errors = _captureErrors();
    await _pump(tester, BandwidthPreference(prefsFactory: _unavailable));
    await _toggle(tester);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(_unsaved, findsNothing);
    expect(errors(), hasLength(1));
  });
}
