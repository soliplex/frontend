import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/status_message_config.dart';
import 'package:soliplex_frontend/src/status_message/status_message.dart';
import 'package:soliplex_frontend/src/status_message/status_message_controller.dart';

const _msg = StatusMessage(
  id: 'm',
  title: 't',
  body: 'b',
  intent: MessageIntent.info,
  category: MessageCategory.general,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start() fetches immediately and publishes the result', () async {
    var calls = 0;
    final c = StatusMessageController(
      fetcher: () async {
        calls++;
        return _msg;
      },
      config: const StatusMessageConfig(pollInterval: Duration(minutes: 5)),
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(c.message.value, _msg);
    c.dispose();
  });

  test('start() is a no-op when config is disabled', () async {
    var calls = 0;
    final c = StatusMessageController(
      fetcher: () async {
        calls++;
        return _msg;
      },
      config: StatusMessageConfig.disabled,
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    expect(c.message.value, isNull);
    c.dispose();
  });

  test('re-fetches every poll interval', () {
    fakeAsync((async) {
      var calls = 0;
      final c = StatusMessageController(
        fetcher: () async {
          calls++;
          return _msg;
        },
        config: const StatusMessageConfig(pollInterval: Duration(minutes: 5)),
      )..start();
      async.flushMicrotasks();
      expect(calls, 1); // immediate fetch

      async.elapse(const Duration(minutes: 5));
      expect(calls, 2); // one poll cycle

      async.elapse(const Duration(minutes: 5));
      expect(calls, 3); // recurs
      c.dispose();
    });
  });

  test('re-fetches on app resume, ignores other lifecycle states', () async {
    var calls = 0;
    final c = StatusMessageController(
      fetcher: () async {
        calls++;
        return _msg;
      },
      config: const StatusMessageConfig(pollInterval: Duration(minutes: 5)),
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1); // paused does not re-fetch

    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2); // resume re-fetches
    c.dispose();
  });

  test('a fetch completing after dispose does not write the disposed signal',
      () async {
    final completer = Completer<StatusMessage?>();
    final c = StatusMessageController(
      fetcher: () => completer.future,
      config: const StatusMessageConfig(pollInterval: Duration(minutes: 5)),
    )..start();

    c.dispose(); // dispose while the initial fetch is in flight
    completer.complete(_msg); // resolves after dispose

    // Must not throw SignalsWriteAfterDisposeError.
    await Future<void>.delayed(Duration.zero);
  });
}
