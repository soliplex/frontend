import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/core/signal_listenable.dart';

void main() {
  group('SignalListenable', () {
    test('notifies on signal change', () {
      final signal = Signal(0);
      final listenable = SignalListenable(signal);

      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      signal.value = 1;

      expect(notifyCount, 1);

      listenable.dispose();
    });

    test('multiple changes produce multiple notifications', () {
      final signal = Signal(0);
      final listenable = SignalListenable(signal);

      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      signal.value = 1;
      signal.value = 2;
      signal.value = 3;

      expect(notifyCount, 3);

      listenable.dispose();
    });

    test('dispose stops notifications', () {
      final signal = Signal(0);
      final listenable = SignalListenable(signal);

      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      signal.value = 1;
      expect(notifyCount, 1);

      listenable.dispose();

      signal.value = 2;
      expect(notifyCount, 1);
    });

    test('works with computed signals', () {
      final a = Signal(1);
      final b = Signal(2);
      final sum = computed(() => a.value + b.value);
      final listenable = SignalListenable(sum);

      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      a.value = 10;
      expect(notifyCount, 1);

      b.value = 20;
      expect(notifyCount, 2);

      listenable.dispose();
    });
  });
}
