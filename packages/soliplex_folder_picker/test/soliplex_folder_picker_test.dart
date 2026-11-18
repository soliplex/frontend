import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_folder_picker/soliplex_folder_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/folder_picker');
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  SoliplexFolderPicker picker() => SoliplexFolderPicker(
        channel: channel,
        platform: TargetPlatform.android,
        isWeb: false,
      );

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('isSupported', () {
    test('is true on Android', () {
      expect(picker().isSupported, isTrue);
    });

    test('is false where no native side is registered', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        final picker = SoliplexFolderPicker(platform: platform, isWeb: false);
        expect(picker.isSupported, isFalse, reason: '$platform');
      }
    });

    test('is false on web, whatever platform the browser reports', () {
      final picker =
          SoliplexFolderPicker(platform: TargetPlatform.android, isWeb: true);
      expect(picker.isSupported, isFalse);
    });

    test('uses the documented channel by default', () {
      expect(SoliplexFolderPicker.channelName, 'ai.soliplex/folder_picker');
    });
  });

  group('pick', () {
    test('answers null on cancel', () async {
      answer((_) async => null);
      expect(await picker().pick(), isNull);
      expect(calls.single.method, 'pick');
    });

    test('lists the folder and its files', () async {
      answer(
        (_) async => {
          'name': 'testdir',
          'files': [
            {'path': 'a.txt', 'uri': 'content://t/a', 'size': 8},
            {'path': 'sub/b.md', 'uri': 'content://t/b', 'size': null},
          ],
        },
      );

      final folder = (await picker().pick())!;

      expect(folder.name, 'testdir');
      expect(folder.files.map((f) => f.relativePath), ['a.txt', 'sub/b.md']);
      expect(
        folder.files.map((f) => f.uri),
        ['content://t/a', 'content://t/b'],
      );
      expect(folder.files.map((f) => f.size), [8, null]);
    });

    test('passes a platform failure through', () async {
      answer((_) async => throw PlatformException(code: 'list_failed'));
      await expectLater(
        picker().pick(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('openRead', () {
    test('reads chunk by chunk, then closes the file', () async {
      final chunks = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3]),
      ];
      answer((call) async {
        switch (call.method) {
          case 'open':
            expect(call.arguments, {'uri': 'content://t/a'});
            return 7;
          case 'read':
            expect(call.arguments, {
              'handle': 7,
              'max': SoliplexFolderPicker.chunkSize,
            });
            return chunks.isEmpty ? null : chunks.removeAt(0);
          case 'close':
            expect(call.arguments, {'handle': 7});
            return null;
        }
        fail('unexpected ${call.method}');
      });

      final bytes = await picker()
          .openRead('content://t/a')
          .expand((chunk) => chunk)
          .toList();

      expect(bytes, [1, 2, 3]);
      expect(calls.map((c) => c.method), [
        'open',
        'read',
        'read',
        'read',
        'close',
      ]);
    });

    test('opens the file afresh on every call', () async {
      var handle = 0;
      answer((call) async => call.method == 'open' ? ++handle : null);
      final reader = picker();

      await reader.openRead('content://t/a').toList();
      await reader.openRead('content://t/a').toList();

      expect(calls.where((c) => c.method == 'open'), hasLength(2));
      expect(
        calls.where((c) => c.method == 'close').map((c) => c.arguments),
        [
          {'handle': 1},
          {'handle': 2},
        ],
      );
    });

    test('closes the file when a read fails', () async {
      answer((call) async {
        if (call.method == 'read') {
          throw PlatformException(code: 'read_failed');
        }
        return call.method == 'open' ? 1 : null;
      });

      await expectLater(
        picker().openRead('content://t/a').toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.last.method, 'close');
    });

    test('closes the file when the listener cancels', () async {
      answer((call) async {
        if (call.method == 'read') return Uint8List.fromList([1]);
        return call.method == 'open' ? 1 : null;
      });

      await picker().openRead('content://t/a').first;
      // The generator's finally runs as the cancel completes.
      await pumpEventQueue();

      expect(calls.last.method, 'close');
    });

    test('does not close a file it could not open', () async {
      answer((call) async => throw PlatformException(code: 'open_failed'));

      await expectLater(
        picker().openRead('content://t/a').toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.map((c) => c.method), ['open']);
    });
  });
}
