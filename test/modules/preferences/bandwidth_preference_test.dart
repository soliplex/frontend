import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';

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

  group('forwardedPropsFor', () {
    late FakeSoliplexApi api;
    late BandwidthPreference preference;
    late ForwardedPropsResolver resolve;

    setUp(() {
      api = FakeSoliplexApi()
        ..sseDeliveryProfiles = [_lowLatency, _lowBandwidth];
      preference = BandwidthPreference();
      resolve = preference.forwardedPropsFor(api, serverId: 'srv');
    });

    test('off sends nothing and asks the server nothing', () async {
      expect(await resolve(), isEmpty);
      expect(api.sseDeliveryProfilesCallCount, 0);
    });

    test("on sends the name of the server's message profile", () async {
      await preference.setLowBandwidth(true);

      expect(await resolve(), {'agui_sse_delivery': 'low_bandwidth'});
    });

    test(
        'on sends nothing when the server has no message profile, and says '
        'so once', () async {
      final warnings = _capture(LogLevel.warning);
      api.sseDeliveryProfiles = [_lowLatency];
      await preference.setLowBandwidth(true);

      expect(await resolve(), isEmpty);
      expect(await resolve(), isEmpty);
      expect(warnings(), hasLength(1));
    });

    test('asks a server once', () async {
      await preference.setLowBandwidth(true);

      await resolve();
      await resolve();

      expect(api.sseDeliveryProfilesCallCount, 1);
    });

    test('a failed lookup sends nothing and asks again next turn', () async {
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError =
          const NetworkException(message: 'Connection refused');
      await preference.setLowBandwidth(true);

      final failed = await resolve();
      final retried = await resolve();

      expect(failed, isEmpty);
      expect(retried, {'agui_sse_delivery': 'low_bandwidth'});
      expect(warnings(), hasLength(1));
    });

    test('a server without the endpoint is asked once, and says so once',
        () async {
      final warnings = _capture(LogLevel.warning);
      api.nextSseDeliveryProfilesError =
          const NotFoundException(message: 'Not found');
      await preference.setLowBandwidth(true);

      expect(await resolve(), isEmpty);
      expect(await resolve(), isEmpty);
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

      expect(await resolve(), {'agui_sse_delivery': 'low_bandwidth'});
      expect(warnings(), hasLength(1));
    });
  });
}
