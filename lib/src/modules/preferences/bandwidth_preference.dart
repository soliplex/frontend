import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.bandwidth_preference');

/// The device-wide low bandwidth mode, and the AG-UI delivery strategy it
/// asks every run for.
///
/// Off — the default, and what a failed read leaves — asks for `bounded`, so
/// replies stream; on asks for `message`, so each reply arrives once
/// complete. Only the strategy is sent: the server owns the bounds.
///
/// Storage is best-effort: a failure is logged and never thrown, because a
/// missing preference must not stop the app starting or a run being sent.
/// The value is not sensitive, so it lives in shared_preferences.
class BandwidthPreference {
  BandwidthPreference({Future<SharedPreferences> Function()? prefsFactory})
      : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const _key = 'soliplex_low_bandwidth_mode';

  final Signal<bool> _lowBandwidth = Signal<bool>(false);
  ReadonlySignal<bool> get lowBandwidth => _lowBandwidth;

  Future<void> load() async {
    try {
      final prefs = await _prefsFactory();
      _lowBandwidth.value = prefs.getBool(_key) ?? false;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error(
        'Failed to read low bandwidth mode; defaulting to off',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Applies [value] at once; returns whether it was saved.
  Future<bool> setLowBandwidth(bool value) async {
    _lowBandwidth.value = value;
    try {
      final prefs = await _prefsFactory();
      // Android reports a failed commit by returning false, not by throwing.
      final saved = await prefs.setBool(_key, value);
      if (!saved) _logger.error('Failed to save low bandwidth mode');
      return saved;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error(
        'Failed to save low bandwidth mode',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Map<String, dynamic> forwardedProps() => {
        'agui_sse_delivery': {
          'strategy': _lowBandwidth.value ? 'message' : 'bounded',
        },
      };
}
