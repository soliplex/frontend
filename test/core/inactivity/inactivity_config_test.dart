import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_config.dart';

void main() {
  group('InactivityConfig', () {
    test('defaults to 10 minute warning and 5 minute grace', () {
      const config = InactivityConfig();

      expect(config.warningDuration, const Duration(minutes: 10));
      expect(config.graceDuration, const Duration(minutes: 5));
    });

    group('isEnabled', () {
      test('true when both durations are positive', () {
        const config = InactivityConfig(
          warningDuration: Duration(seconds: 1),
          graceDuration: Duration(seconds: 1),
        );

        expect(config.isEnabled, isTrue);
      });

      test('false when warning duration is zero', () {
        const config = InactivityConfig(
          warningDuration: Duration.zero,
          graceDuration: Duration(seconds: 1),
        );

        expect(config.isEnabled, isFalse);
      });

      test('false when grace duration is zero', () {
        const config = InactivityConfig(
          warningDuration: Duration(seconds: 1),
          graceDuration: Duration.zero,
        );

        expect(config.isEnabled, isFalse);
      });
    });

    test('disabled has zero durations and is not enabled', () {
      expect(InactivityConfig.disabled.warningDuration, Duration.zero);
      expect(InactivityConfig.disabled.graceDuration, Duration.zero);
      expect(InactivityConfig.disabled.isEnabled, isFalse);
    });
  });
}
