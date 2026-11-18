import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/markdown/launch_markdown_link.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed launch logs no part of the link', () async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // What url_launcher_android throws when no app handles the link.
    messenger.setMockMethodCallHandler(channel, (call) async {
      final url = (call.arguments as Map)['url'];
      throw PlatformException(
        code: 'ACTIVITY_NOT_FOUND',
        message: 'No Activity found to handle intent { $url }',
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(LogManager.instance.reset);

    await launchMarkdownLink('https://cdn.example/clip.mp4?sig=secret');

    final record = sink.records.single;
    expect(record.message, contains('scheme: https'));
    expect(record.attributes['failure'], contains('PlatformException'));
    expect(
      '${record.message} ${record.attributes} ${record.error}',
      isNot(contains('secret')),
    );
  });
}
