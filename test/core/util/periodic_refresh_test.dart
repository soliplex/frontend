import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/util/periodic_refresh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fires every interval once started, not before', () {
    fakeAsync((async) {
      var calls = 0;
      final r = PeriodicRefresh(
        interval: const Duration(seconds: 30),
        onRefresh: () => calls++,
      )..start();

      async.elapse(const Duration(seconds: 29));
      expect(calls, 0);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      async.elapse(const Duration(seconds: 30));
      expect(calls, 2);
      r.dispose();
    });
  });

  test('skips ticks while hidden and fires once on becoming visible', () {
    fakeAsync((async) {
      var calls = 0;
      final r = PeriodicRefresh(
        interval: const Duration(seconds: 30),
        onRefresh: () => calls++,
      )..start();

      r.didChangeAppLifecycleState(AppLifecycleState.hidden);
      async.elapse(const Duration(minutes: 5));
      expect(calls, 0);

      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 1);
      r.dispose();
    });
  });

  test('a blur that leaves the app visible neither skips nor refreshes', () {
    fakeAsync((async) {
      var calls = 0;
      final r = PeriodicRefresh(
        interval: const Duration(seconds: 30),
        onRefresh: () => calls++,
      )..start();

      r.didChangeAppLifecycleState(AppLifecycleState.inactive);
      async.elapse(const Duration(seconds: 30));
      expect(calls, 1);

      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 1);
      r.dispose();
    });
  });

  test('stops firing after dispose', () {
    fakeAsync((async) {
      var calls = 0;
      final r = PeriodicRefresh(
        interval: const Duration(seconds: 30),
        onRefresh: () => calls++,
      )..start();
      r.dispose();

      async.elapse(const Duration(minutes: 5));
      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 0);
    });
  });
}
