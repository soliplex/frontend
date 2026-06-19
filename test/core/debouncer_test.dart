import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/debouncer.dart';

void main() {
  test('coalesces a burst within the window into one trailing call', () {
    fakeAsync((async) {
      final debouncer = Debouncer(const Duration(milliseconds: 300));
      var calls = 0;
      debouncer.run(() => calls++);
      async.elapse(const Duration(milliseconds: 100));
      debouncer.run(() => calls++);
      async.elapse(const Duration(milliseconds: 100));
      debouncer.run(() => calls++);
      expect(calls, 0, reason: 'still within the window after the last run');
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1, reason: 'burst coalesces to a single trailing call');
    });
  });

  test('honors the latest action (trailing edge)', () {
    fakeAsync((async) {
      final debouncer = Debouncer(const Duration(milliseconds: 300));
      final fired = <int>[];
      debouncer.run(() => fired.add(1));
      async.elapse(const Duration(milliseconds: 100));
      debouncer.run(() => fired.add(2));
      async.elapse(const Duration(milliseconds: 300));
      expect(fired, [2]);
    });
  });

  test('runs again for a call spaced beyond the window', () {
    fakeAsync((async) {
      final debouncer = Debouncer(const Duration(milliseconds: 300));
      var calls = 0;
      debouncer.run(() => calls++);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1);
      debouncer.run(() => calls++);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 2);
    });
  });

  test('cancel prevents a pending action from firing', () {
    fakeAsync((async) {
      final debouncer = Debouncer(const Duration(milliseconds: 300));
      var calls = 0;
      debouncer.run(() => calls++);
      debouncer.cancel();
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 0);
    });
  });
}
