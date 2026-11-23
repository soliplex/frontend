import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_row_download_action.dart';
import 'package:soliplex_frontend/src/modules/room/ui/start_download.dart';

import '../../../helpers/test_downloads.dart';

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
      await pumpAction(tester, _sized(largeDownloadWarningBytes + 1));

      await tester.tap(find.byTooltip('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download large file?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });

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
    });

    testWidgets('a small file downloads without asking', (tester) async {
      await pumpAction(tester, _sized(1024));

      await tester.tap(find.byTooltip('Download'));
      await tester.pump();

      expect(find.text('Download large file?'), findsNothing);
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

    expect(find.text('Download large file?'), findsNothing);
    expect(saved, ['dataset.csv']);
    await tester.pump(const Duration(seconds: 2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
