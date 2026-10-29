import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_entry_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';
import 'package:soliplex_frontend/src/shared/selectable_content.dart';

// The file panel and room info hold their entries inside a SelectableContent,
// whose long press selects a word on touch. An entry's name shows its full
// name on a long press instead, as it does on hover; a failure's reason stays
// selectable, so it can be copied into a report.

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: SelectableContent(
          child: Column(
            children: [
              UploadEntryRow(
                entry: PersistedUpload(
                  filename: 'stored.csv',
                  url: Uri.parse('https://example.test/stored.csv'),
                ),
                onCancel: (_) {},
                onDismiss: (_) {},
              ),
              UploadEntryRow(
                entry: FailedUpload(
                  id: 'f',
                  filename: 'failed.csv',
                  message: 'Too big',
                ),
                onCancel: (_) {},
                onDismiss: (_) {},
              ),
              WorkspaceFilesSection(
                status: WorkdirFilesLoaded([
                  WorkdirFile(
                    filename: 'reports/summary.md',
                    url: Uri.parse('https://example.test/summary.md'),
                  ),
                ]),
                onDownload: (_) async => DownloadOutcome.success,
                onFetchBytes: (_) async => Uint8List(0),
                onRetry: () {},
                folderToggles: const {},
                onFolderToggled: (_, {required expanded}) {},
              ),
            ],
          ),
        ),
      ),
    ));

Future<void> _longPress(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  await tester.pump(const Duration(milliseconds: 100));
}

bool _selecting() =>
    find.byType(AdaptiveTextSelectionToolbar).evaluate().isNotEmpty;

void main() {
  final touch = TargetPlatformVariant(
    {TargetPlatform.iOS, TargetPlatform.android},
  );

  // Each name is on screen once; its tooltip shows it a second time.
  for (final (name, shown) in [
    ('stored.csv', 'stored.csv'),
    ('failed.csv', 'failed.csv'),
    ('summary.md', 'reports/summary.md'),
    ('reports', 'reports'),
  ]) {
    testWidgets(
      'a long press on $name shows its tooltip',
      (tester) async {
        await _pump(tester);
        final onScreen = find.text(shown).evaluate().length;

        await _longPress(
          tester,
          name == 'summary.md' ? find.text('summary') : find.text(name),
        );

        expect(find.text(shown), findsNWidgets(onScreen + 1));
        expect(_selecting(), isFalse);
      },
      variant: touch,
    );
  }

  testWidgets(
    "a long press on a failure's reason selects it",
    (tester) async {
      await _pump(tester);

      await _longPress(tester, find.text('Too big'));

      expect(_selecting(), isTrue);
    },
    variant: touch,
  );
}
