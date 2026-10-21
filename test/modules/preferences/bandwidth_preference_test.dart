import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

const _bounded = {
  'agui_sse_delivery': {'strategy': 'bounded'},
};
const _message = {
  'agui_sse_delivery': {'strategy': 'message'},
};

/// Storage that refuses the write without throwing, as Android does when
/// `commit()` fails.
class _RefusingPrefs extends Fake implements SharedPreferences {
  @override
  Future<bool> setBool(String key, bool value) async => false;
}

BandwidthPreference _failing() => BandwidthPreference(
      prefsFactory: () => Future.error(StateError('prefs unavailable')),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('is off and asks for bounded before anything is stored', () async {
    final preference = BandwidthPreference();

    await preference.load();

    expect(preference.lowBandwidth.value, isFalse);
    expect(preference.forwardedProps(), _bounded);
  });

  test('asks for message when on', () async {
    final preference = BandwidthPreference();

    await preference.setLowBandwidth(true);

    expect(preference.forwardedProps(), _message);
  });

  test('survives a restart', () async {
    await BandwidthPreference().setLowBandwidth(true);

    final restarted = BandwidthPreference();
    await restarted.load();

    expect(restarted.lowBandwidth.value, isTrue);
  });

  test('a read failure leaves it off', () async {
    final errors = _captureErrors();
    final preference = _failing();

    await preference.load();

    expect(preference.lowBandwidth.value, isFalse);
    expect(errors(), hasLength(1));
  });

  test('a refused write reports it unsaved', () async {
    final errors = _captureErrors();
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
    final errors = _captureErrors();
    final preference = _failing();

    final saved = await preference.setLowBandwidth(true);

    expect(saved, isFalse);
    expect(preference.lowBandwidth.value, isTrue);
    expect(errors(), hasLength(1));
  });
}
