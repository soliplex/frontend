import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_entry_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

// The file panel and room info hold their entries inside a SelectableContent,
// a SelectionArea. A file's name labels the file, as in a file manager: it
// cannot be selected, and shows its full name on hover or, on touch, a long
// press. A failure's reason stays selectable, so it can be copied into a
// report.

String? _selected;

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: SelectionArea(
          onSelectionChanged: (content) => _selected = content?.plainText,
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

Future<void> _mouseDragAcross(WidgetTester tester, Finder target) async {
  final rect = tester.getRect(target);
  final drag = await tester.startGesture(
    rect.centerLeft + const Offset(1, 0),
    kind: PointerDeviceKind.mouse,
  );
  await drag.moveTo(rect.centerRight - const Offset(1, 0));
  await drag.up();
  await tester.pump();
}

void main() {
  setUp(() => _selected = null);

  for (final name in ['stored.csv', 'failed.csv', 'summary', 'reports']) {
    testWidgets('a mouse drag across $name selects nothing', (tester) async {
      await _pump(tester);

      await _mouseDragAcross(tester, find.text(name));

      expect(_selected ?? '', isEmpty);
    });
  }

  testWidgets("a mouse drag across a failure's reason selects it",
      (tester) async {
    await _pump(tester);

    await _mouseDragAcross(tester, find.text('Too big'));

    expect(_selected, 'Too big');
  });

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
