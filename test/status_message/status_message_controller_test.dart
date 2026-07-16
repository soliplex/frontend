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
}
