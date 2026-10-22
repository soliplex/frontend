import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_frontend/src/modules/preferences/preferences_screen.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

Future<void> _pump(
  WidgetTester tester,
  BandwidthPreference preference, {
  List<ServerEntry> servers = const [],
  // A check in flight spins forever, so a test watching one cannot settle.
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: PreferencesScreen(
        appName: 'Acme',
        preference: preference,
        servers: Signal({for (final s in servers) s.serverId: s}),
      ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

ServerEntry _server(String name, FakeSoliplexApi api) => createTestServerEntry(
      serverId: 'https://$name.example',
      name: name,
      api: api,
    );

/// A preference loaded with low bandwidth mode on.
Future<BandwidthPreference> _on(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'soliplex_low_bandwidth_mode': true});
  final preference = BandwidthPreference();
  await tester.runAsync(preference.load);
  return preference;
}

Iterable<LogRecord> Function() _captureWarnings() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => sink.records.where(
        (r) =>
            r.level == LogLevel.warning &&
            r.loggerName == 'soliplex.bandwidth_preference',
      );
}

const _messageProfile =
    SseDeliveryProfile(name: 'low_bandwidth', strategy: 'message');
const _boundedProfile =
    SseDeliveryProfile(name: 'low_latency', strategy: 'bounded');

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

  testWidgets('with the mode on, names the servers that do not offer it',
      (tester) async {
    final warnings = _captureWarnings();
    final preference = await _on(tester);

    await _pump(
      tester,
      preference,
      servers: [
        _server('Alpha',
            FakeSoliplexApi()..sseDeliveryProfiles = [_messageProfile]),
        _server(
            'Beta', FakeSoliplexApi()..sseDeliveryProfiles = [_boundedProfile]),
      ],
    );

    expect(find.text('Not available on: Beta'), findsOneWidget);
    expect(find.textContaining('Alpha'), findsNothing);
    expect(warnings(), hasLength(1));
  });

  testWidgets('a server that could not be checked is listed apart',
      (tester) async {
    final warnings = _captureWarnings();
    final preference = await _on(tester);

    await _pump(
      tester,
      preference,
      servers: [
        _server(
          'Gamma',
          FakeSoliplexApi()
            ..nextSseDeliveryProfilesError =
                const NetworkException(message: 'Connection refused'),
        ),
      ],
    );

    expect(find.text("Couldn't check: Gamma"), findsOneWidget);
    expect(find.textContaining('Not available on'), findsNothing);
    expect(warnings(), hasLength(1));
  });

  testWidgets('says so while the servers are being checked', (tester) async {
    final preference = await _on(tester);
    final held = Completer<void>();
    final api = FakeSoliplexApi()
      ..sseDeliveryProfiles = [_messageProfile]
      ..sseDeliveryProfilesGate = held;

    await _pump(
      tester,
      preference,
      servers: [_server('Alpha', api)],
      settle: false,
    );
    expect(find.text('Checking servers…'), findsOneWidget);

    held.complete();
    await tester.pumpAndSettle();
    expect(find.text('Checking servers…'), findsNothing);
  });

  testWidgets('nothing is listed or checked while the mode is off',
      (tester) async {
    final preference = BandwidthPreference();
    await tester.runAsync(preference.load);
    final api = FakeSoliplexApi()..sseDeliveryProfiles = [_boundedProfile];

    await _pump(tester, preference, servers: [_server('Beta', api)]);

    expect(find.textContaining('Not available on'), findsNothing);
    expect(api.sseDeliveryProfilesCallCount, 0);
  });

  testWidgets('turning the mode on checks the servers', (tester) async {
    final warnings = _captureWarnings();
    final preference = BandwidthPreference();
    await tester.runAsync(preference.load);

    await _pump(
      tester,
      preference,
      servers: [
        _server(
            'Beta', FakeSoliplexApi()..sseDeliveryProfiles = [_boundedProfile]),
      ],
    );
    await _toggle(tester);

    expect(find.text('Not available on: Beta'), findsOneWidget);
    expect(warnings(), hasLength(1));
  });
}
