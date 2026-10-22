import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

ServerConnection _connection(String serverId, FakeSoliplexApi api) =>
    ServerConnection(
      serverId: serverId,
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

const _lowLatency =
    SseDeliveryProfile(name: 'low_latency', strategy: 'bounded');
const _lowBandwidth =
    SseDeliveryProfile(name: 'low_bandwidth', strategy: 'message');

/// Storage that refuses the write without throwing, as Android does when
/// `commit()` fails.
class _RefusingPrefs extends Fake implements SharedPreferences {
  @override
  Future<bool> setBool(String key, bool value) async => false;
}

BandwidthPreference _failing() => BandwidthPreference(
      prefsFactory: () => Future.error(StateError('prefs unavailable')),
    );

/// Captures this module's records at [level] for the test.
Iterable<LogRecord> Function() _capture([LogLevel level = LogLevel.error]) {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => sink.records.where(
        (r) =>
            r.level == level && r.loggerName == 'soliplex.bandwidth_preference',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('is off before anything is stored', () async {
    final preference = BandwidthPreference();

    await preference.load();

    expect(preference.lowBandwidth.value, isFalse);
  });

  test('survives a restart', () async {
    await BandwidthPreference().setLowBandwidth(true);

    final restarted = BandwidthPreference();
    await restarted.load();

    expect(restarted.lowBandwidth.value, isTrue);
  });

  test('a read failure leaves it off', () async {
    final errors = _capture();
    final preference = _failing();

    await preference.load();

    expect(preference.lowBandwidth.value, isFalse);
    expect(errors(), hasLength(1));
  });

  test('a refused write reports it unsaved', () async {
    final errors = _capture();
    final preference = BandwidthPreference(
      prefsFactory: () async => _RefusingPrefs(),
    );

    final saved = await preference.setLowBandwidth(true);

    expect(saved, isFalse);
    expect(preference.lowBandwidth.value, isTrue);
    expect(errors(), hasLength(1));
  });

  test('a write failure still applies the value and reports it unsaved',
      () async {
    final errors = _capture();
    final preference = _failing();

    final saved = await preference.setLowBandwidth(true);

    expect(saved, isFalse);
    expect(preference.lowBandwidth.value, isTrue);
    expect(errors(), hasLength(1));
  });

  group('server profiles', () {
    late FakeSoliplexApi api;
    late ServerConnection connection;
    late BandwidthPreference preference;
    late ForwardedPropsResolver resolve;

    setUp(() {
      api = FakeSoliplexApi()
        ..sseDeliveryProfiles = [_lowLatency, _lowBandwidth];
      connection = _connection('srv', api);
      preference = BandwidthPreference();
      resolve = preference.forwardedPropsFor(connection);
    });

    test('off sends nothing and asks the server nothing', () async {
      expect(resolve(), isEmpty);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 0);
    });

    test('a turn before any answer sends nothing and asks the server once',
        () async {
      await preference.setLowBandwidth(true);

      expect(resolve(), isEmpty);
      expect(preference.forwardedPropsFor(connection)(), isEmpty);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 1);
      expect(resolve(), {'agui_sse_delivery': 'low_bandwidth'});
    });

    test(
        'no message profile sends nothing, says so once, and is not asked '
        'again', () async {
      final warnings = _capture(LogLevel.warning);
      api.sseDeliveryProfiles = [_lowLatency];
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);

      expect(resolve(), isEmpty);
      expect(resolve(), isEmpty);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 1);
      expect(warnings(), hasLength(1));
    });

    test('a failed lookup sends nothing and the next turn asks again',
        () async {
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError =
          const NetworkException(message: 'Connection refused');
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);

      expect(resolve(), isEmpty);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 2);
      expect(resolve(), {'agui_sse_delivery': 'low_bandwidth'});
      expect(warnings(), hasLength(1));
    });

    test('a failed lookup logs the failure shape, not the failure', () async {
      // A non-network failure can carry the response it failed on, so only
      // its shape and status may reach the record.
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError = const ApiException(
        message: 'body the server sent',
        statusCode: 502,
      );
      await preference.setLowBandwidth(true);

      await preference.checkServers([connection]);

      final record = warnings().single;
      expect(record.error, isNull);
      expect(record.attributes['statusCode'], 502);
      expect(record.attributes['failure'], isNotNull);
      expect(record.toString(), isNot(contains('body the server sent')));
    });

    test('a server without the endpoint is asked once', () async {
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError =
          const NotFoundException(message: 'Not found');
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);

      expect(resolve(), isEmpty);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 1);
      expect(warnings(), hasLength(1));
    });

    test('two message profiles: sends the first and warns', () async {
      final warnings = _capture(LogLevel.warning);
      api.sseDeliveryProfiles = [
        _lowBandwidth,
        const SseDeliveryProfile(name: 'whole', strategy: 'message'),
      ];
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);

      expect(resolve(), {'agui_sse_delivery': 'low_bandwidth'});
      expect(warnings(), hasLength(1));
    });

    test('a re-check keeps sending the profile already known', () async {
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);
      api.sseDeliveryProfilesGate = Completer<void>();

      unawaited(preference.checkServers([connection]));

      expect(preference.checkingServers.value, contains('srv'));
      expect(resolve(), {'agui_sse_delivery': 'low_bandwidth'});
    });

    test('checking servers replaces a stale profile', () async {
      await preference.setLowBandwidth(true);
      await preference.checkServers([connection]);
      api.sseDeliveryProfiles = [
        const SseDeliveryProfile(name: 'saver', strategy: 'message'),
      ];

      await preference.checkServers([connection]);

      expect(resolve(), {'agui_sse_delivery': 'saver'});
    });

    test('checking servers reports what each one offers', () async {
      final noProfile = _connection(
          'no-profile', FakeSoliplexApi()..sseDeliveryProfiles = [_lowLatency]);
      final unreachable = _connection(
        'unreachable',
        FakeSoliplexApi()
          ..nextSseDeliveryProfilesError =
              const NetworkException(message: 'Connection refused'),
      );
      final warnings = _capture(LogLevel.warning);

      await preference.checkServers([connection, noProfile, unreachable]);

      final lookups = preference.profileLookups.value;
      expect(
        lookups['srv'],
        isA<ProfileOffered>().having((p) => p.name, 'name', 'low_bandwidth'),
      );
      expect(lookups['no-profile'], isA<ProfileNotOffered>());
      expect(lookups['unreachable'], isA<ProfileCouldNotCheck>());
      expect(warnings(), hasLength(2));
    });

    test("an older lookup's late answer does not overwrite a newer one",
        () async {
      final held = Completer<void>();
      api.sseDeliveryProfilesGate = held;
      final first = preference.checkServers([connection]);
      api
        ..sseDeliveryProfilesGate = null
        ..sseDeliveryProfiles = [
          const SseDeliveryProfile(name: 'saver', strategy: 'message'),
        ];
      await preference.checkServers([connection]);

      held.complete();
      await first;

      expect(
        preference.profileLookups.value['srv'],
        isA<ProfileOffered>().having((p) => p.name, 'name', 'saver'),
      );
    });
  });

  group('trackServers', () {
    late Signal<Map<String, ServerEntry>> servers;
    late FakeSoliplexApi api;
    late BandwidthPreference preference;

    setUp(() {
      servers = Signal(const {});
      api = FakeSoliplexApi()..sseDeliveryProfiles = [_lowBandwidth];
      preference = BandwidthPreference();
      addTearDown(preference.trackServers(servers));
    });

    void addServer(String serverId) => servers.value = {
          ...servers.value,
          serverId: createTestServerEntry(serverId: serverId, api: api),
        };

    test('while off, looks nothing up', () async {
      addServer('https://a.example');
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 0);
    });

    test('turning on looks up the servers already known', () async {
      addServer('https://a.example');
      await preference.setLowBandwidth(true);
      await pumpEventQueue();

      expect(
        preference.profileLookups.value['https://a.example'],
        isA<ProfileOffered>(),
      );
    });

    test('turning the mode on again looks every server up again', () async {
      addServer('https://a.example');
      await preference.setLowBandwidth(true);
      await pumpEventQueue();
      await preference.setLowBandwidth(false);

      await preference.setLowBandwidth(true);
      await pumpEventQueue();

      expect(api.sseDeliveryProfilesCallCount, 2);
    });

    test(
        'while on, a server whose lookup failed is asked again when the '
        'servers change', () async {
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError =
          const NetworkException(message: 'Connection refused');
      await preference.setLowBandwidth(true);
      addServer('https://a.example');
      await pumpEventQueue();

      addServer('https://b.example');
      await pumpEventQueue();

      expect(
        preference.profileLookups.value['https://a.example'],
        isA<ProfileOffered>(),
      );
      expect(warnings(), hasLength(1));
    });

    test('while on, a server that appears is looked up', () async {
      await preference.setLowBandwidth(true);
      addServer('https://b.example');
      await pumpEventQueue();

      expect(
        preference.profileLookups.value['https://b.example'],
        isA<ProfileOffered>(),
      );
      expect(api.sseDeliveryProfilesCallCount, 1);
    });
  });
}
