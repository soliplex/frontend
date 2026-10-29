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

// Every kind of entry the file panel and room info list, side by side: the
// list reads as one only if they share a height and their icons share
// columns.

const _longName = 'quarterly_financial_reports_archive_2026_final_v2.xlsx';

PersistedUpload _stored(String name, {bool isDeleting = false}) =>
    PersistedUpload(
      filename: name,
      url: Uri.parse('https://example.test/$name'),
      isDeleting: isDeleting,
    );

Widget _upload(DisplayUpload entry, {bool canDelete = false}) => UploadEntryRow(
      entry: entry,
      onCancel: (_) {},
      onDismiss: (_) {},
      onDelete: canDelete ? (_) {} : null,
    );

Future<void> _pump(WidgetTester tester, List<Widget> rows) async {
  tester.view.physicalSize = const Size(260, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    ),
  ));
}

Widget _workspace(List<String> paths) => WorkspaceFilesSection(
      status: WorkdirFilesLoaded([
        for (final p in paths)
          WorkdirFile(filename: p, url: Uri.parse('https://example.test/$p')),
      ]),
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List(0),
      onRetry: () {},
      folderToggles: const {},
      onFolderToggled: (_, {required expanded}) {},
    );

double _height(WidgetTester tester, Finder row) => tester.getSize(row).height;

Finder _uploadRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(UploadEntryRow));

Finder _workspaceRow(String name) => find.ancestor(
      of: find.bySemanticsLabel(name),
      matching: find.byType(WorkdirFileRow),
    );

void main() {
  testWidgets('every entry is as tall as the others', (tester) async {
    await _pump(tester, [
      _upload(_stored('room.csv'), canDelete: true),
      _upload(_stored('thread.csv')),
      _upload(_stored(_longName)),
      _upload(_stored('deleting.csv', isDeleting: true), canDelete: true),
      _upload(PendingUpload(
        id: 'p',
        filename: 'pending.csv',
        sentBytes: 1,
        totalBytes: 2,
      )),
      _workspace(['notes.md', 'archive.bin', 'reports/a.csv']),
    ]);

    final folder = find
        .ancestor(of: find.text('reports'), matching: find.byType(InkWell))
        .first;
    final heights = {
      'room upload': _height(tester, _uploadRow('room.csv')),
      'thread upload': _height(tester, _uploadRow('thread.csv')),
      'long name': _height(tester, find.byType(UploadEntryRow).at(2)),
      'deleting': _height(tester, _uploadRow('deleting.csv')),
      'pending': _height(tester, _uploadRow('pending.csv')),
      'previewable': _height(tester, _workspaceRow('notes.md')),
      'download only': _height(tester, _workspaceRow('archive.bin')),
      'folder': _height(tester, folder),
    };
    expect(
      heights.values.toSet(),
      hasLength(1),
      reason: '$heights',
    );
  });

  testWidgets('every failure is as tall as the others', (tester) async {
    await _pump(tester, [
      _upload(FailedUpload(id: 'a', filename: 'a.csv', message: 'Too big')),
      _upload(FailedUpload(
        id: 'b',
        filename: _longName,
        message: "File uploads aren't configured on this server.",
      )),
    ]);

    final rows = find.byType(UploadEntryRow);
    expect(_height(tester, rows.at(0)), _height(tester, rows.at(1)));
  });

  testWidgets('an action is a touch target as tall as its row', (tester) async {
    await _pump(tester, [
      _workspace(['notes.md'])
    ]);

    final row = tester.getSize(_workspaceRow('notes.md'));
    for (final tooltip in ['Preview', 'Download']) {
      final target = tester.getSize(find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(InkWell),
      ));
      expect(target, const Size.square(32), reason: tooltip);
      expect(row.height, target.height, reason: tooltip);
    }
  });

  testWidgets('neighbouring actions touch, with their icons apart',
      (tester) async {
    await _pump(tester, [
      _workspace(['notes.md'])
    ]);

    Rect target(String tooltip) => tester.getRect(find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(InkWell),
        ));
    expect(target('Download').left, target('Preview').right);
    final eye = tester.getRect(find.byIcon(Icons.visibility_outlined));
    final download = tester.getRect(find.byIcon(Icons.download_outlined));
    expect(download.left - eye.right, 2 * SoliplexSpacing.s2);
  });

  testWidgets('a delete under way spins where its button was', (tester) async {
    await _pump(tester, [
      _upload(_stored('room.csv'), canDelete: true),
      _upload(_stored('deleting.csv', isDeleting: true), canDelete: true),
    ]);

    final delete = tester.getRect(find.byIcon(Icons.delete_outline));
    final spinner = tester.getRect(find.descendant(
      of: _uploadRow('deleting.csv'),
      matching: find.byType(CircularProgressIndicator),
    ));
    expect(spinner.center.dx, delete.center.dx);
  });

  testWidgets('icons and actions keep one column in every state',
      (tester) async {
    await _pump(tester, [
      _upload(_stored('room.csv'), canDelete: true),
      _upload(PendingUpload(
        id: 'p',
        filename: 'pending.csv',
        sentBytes: 1,
        totalBytes: 2,
      )),
      _upload(FailedUpload(id: 'f', filename: 'f.csv', message: 'Too big')),
      _workspace(['archive.bin']),
    ]);

    final delete = tester.getRect(find.byIcon(Icons.delete_outline));
    final download = tester.getRect(find.byIcon(Icons.download_outlined));
    final closes = find.byIcon(Icons.close);
    final cancel = tester.getRect(closes.at(0));
    final dismiss = tester.getRect(closes.at(1));
    expect(
      {delete.right, download.right, cancel.right, dismiss.right},
      hasLength(1),
      reason: 'the trailing actions share a column',
    );
    expect(
      {delete.size, download.size, cancel.size, dismiss.size},
      hasLength(1),
      reason: 'the actions are drawn at one size',
    );

    final storedIcon = tester.getRect(
      find
          .descendant(
            of: _uploadRow('room.csv'),
            matching: find.byType(Icon),
          )
          .first,
    );
    final failedIcon = tester.getRect(find.byIcon(Icons.error_outline));
    expect(failedIcon.left, storedIcon.left,
        reason: 'a failed row keeps the leading column');
  });
}
