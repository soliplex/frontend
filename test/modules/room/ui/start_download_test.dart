import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_row_download_action.dart';
import 'package:soliplex_frontend/src/modules/room/ui/start_download.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../helpers/test_downloads.dart';

/// The native platforms that ask before a large download.
final _mobile =
    TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});

WorkdirFile _sized(int? bytes) => WorkdirFile(
      filename: 'dataset.csv',
      url: Uri.parse('https://example.test/dataset.csv'),
      sizeBytes: bytes,
    );

void main() {
  group('warnsBeforeDownload', () {
    const over = largeDownloadWarningBytes + 1;

    test('warns on mobile and the web for a file listed over the threshold',
        () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          warnsBeforeDownload(over, isWeb: false, platform: platform),
          isTrue,
          reason: '$platform',
        );
      }
      expect(
        warnsBeforeDownload(over, isWeb: true, platform: TargetPlatform.macOS),
        isTrue,
        reason: 'the web, whatever the host',
      );
    });

    test('never warns on desktop', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          warnsBeforeDownload(over, isWeb: false, platform: platform),
          isFalse,
          reason: '$platform',
        );
      }
    });

    test('does not warn at the threshold', () {
      expect(
        warnsBeforeDownload(
          largeDownloadWarningBytes,
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });
  });

  group('a large download on mobile', () {
    late List<String> saved;

    Future<void> pumpAction(WidgetTester tester, WorkdirFile file) async {
      saved = [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileRowDownloadAction(
            file: file,
            downloads: testDownloads((file) async {
              saved.add(file.filename);
              return const DownloadSaved();
            }),
          ),
        ),
      ));
    }

    testWidgets('asks first, and downloads nothing when cancelled',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      final level = LogManager.instance.minimumLevel;
      LogManager.instance.minimumLevel = LogLevel.debug;
      addTearDown(() {
        LogManager.instance.minimumLevel = level;
        LogManager.instance.removeSink(sink);
      });
      await pumpAction(tester, _sized(largeDownloadWarningBytes + 1));

      await tester.tap(find.byTooltip('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download dataset.csv?'), findsOneWidget);
      expect(
        find.text("If this device doesn't have enough memory for this "
            'download (100 MB), the app could close before the file is '
            'saved.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      // Recorded, so a download that never ran shows in the diagnostics log.
      final record = sink.records.singleWhere(
        (r) => r.message == 'large download declined',
      );
      expect(record.level, LogLevel.debug);
      expect(record.attributes['filename'], 'dataset.csv');
      expect(record.attributes['sizeBytes'], largeDownloadWarningBytes + 1);
    }, variant: _mobile);

    testWidgets('downloads once the user confirms', (tester) async {
      await pumpAction(tester, _sized(largeDownloadWarningBytes + 1));

      await tester.tap(find.byTooltip('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Download'),
      ));
      await tester.pump();

      expect(saved, ['dataset.csv']);
      await tester.pump(const Duration(seconds: 2));
    }, variant: _mobile);

    testWidgets('a file with no listed size downloads without asking',
        (tester) async {
      await pumpAction(tester, _sized(null));

      await tester.tap(find.byTooltip('Download'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(saved, ['dataset.csv']);
      await tester.pump(const Duration(seconds: 2));
    }, variant: _mobile);

    testWidgets('a small file downloads without asking', (tester) async {
      await pumpAction(tester, _sized(1024));

      await tester.tap(find.byTooltip('Download'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(saved, ['dataset.csv']);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('a large download on desktop does not ask', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FileRowDownloadAction(
          file: _sized(largeDownloadWarningBytes + 1),
          downloads: testDownloads((file) async {
            saved.add(file.filename);
            return const DownloadSaved();
          }),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Download'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, ['dataset.csv']);
    await tester.pump(const Duration(seconds: 2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
