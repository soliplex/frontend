import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_entry_row.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

void main() {
  final cancelled = <String>[];
  final dismissed = <String>[];
  final deleted = <String>[];

  setUp(() {
    cancelled.clear();
    dismissed.clear();
    deleted.clear();
  });

  Future<void> pumpRow(
    WidgetTester tester,
    DisplayUpload entry, {
    bool canDelete = false,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: Scaffold(
            body: UploadEntryRow(
              entry: entry,
              onCancel: cancelled.add,
              onDismiss: dismissed.add,
              onDelete: canDelete ? deleted.add : null,
            ),
          ),
        ),
      );

  PersistedUpload stored({bool isDeleting = false}) => PersistedUpload(
        filename: 'report.pdf',
        url: Uri.parse('https://example.com/report.pdf'),
        isDeleting: isDeleting,
      );

  testWidgets('a pending upload can be cancelled', (tester) async {
    await pumpRow(
      tester,
      const PendingUpload(
        id: 'p1',
        filename: 'report.pdf',
        sentBytes: 5,
        totalBytes: 10,
      ),
    );

    await tester.tap(find.byTooltip('Cancel upload'));

    expect(cancelled, ['p1']);
    expect(dismissed, isEmpty);
  });

  testWidgets('once every byte is sent, an upload offers no cancel',
      (tester) async {
    // The server keeps an upload whose request is aborted after its last
    // byte, so a cancel then would report a file that still lands.
    await pumpRow(
      tester,
      const PendingUpload(
        id: 'p1',
        filename: 'report.pdf',
        sentBytes: 10,
        totalBytes: 10,
      ),
    );

    expect(find.byTooltip('Cancel upload'), findsNothing);
  });

  testWidgets('an upload of unknown length can be cancelled', (tester) async {
    // With no length, nothing says every byte is sent.
    await pumpRow(
      tester,
      const PendingUpload(
        id: 'p1',
        filename: 'report.pdf',
        sentBytes: 10,
        totalBytes: 0,
      ),
    );

    expect(find.byTooltip('Cancel upload'), findsOneWidget);
  });

  testWidgets('a failed upload shows why and can be dismissed', (tester) async {
    await pumpRow(
      tester,
      const FailedUpload(
        id: 'f1',
        filename: 'report.pdf',
        message: 'File is too large to upload.',
      ),
    );

    expect(find.text('File is too large to upload.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));

    expect(dismissed, ['f1']);
    expect(cancelled, isEmpty);
  });

  testWidgets('a persisted upload offers no action', (tester) async {
    await pumpRow(
      tester,
      PersistedUpload(
        filename: 'report.pdf',
        url: Uri.parse('https://example.com/report.pdf'),
      ),
    );

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('a stored file is deleted once the user confirms',
      (tester) async {
    await pumpRow(tester, stored(), canDelete: true);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('report.pdf" for everyone'), findsOneWidget);
    await tester.tap(find.widgetWithText(SoliplexButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, ['report.pdf']);
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    await pumpRow(tester, stored(), canDelete: true);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isEmpty);
  });

  testWidgets('a file being deleted shows progress in place of delete',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRow(tester, stored(isDeleting: true), canDelete: true);

      expect(find.byTooltip('Delete'), findsNothing);
      // A status, because a browser exposes a label on a node with no role
      // to nothing that reads it.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Deleting'))
            .getSemanticsData()
            .role,
        SemanticsRole.status,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('only a stored file offers delete', (tester) async {
    await pumpRow(
      tester,
      const FailedUpload(id: 'f1', filename: 'report.pdf', message: 'No.'),
      canDelete: true,
    );

    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('the delete button is announced once', (tester) async {
    // A browser reads a node's label and then its tooltip, so a tooltip that
    // repeats the label reads "Delete Delete".
    final semantics = tester.ensureSemantics();
    try {
      await pumpRow(tester, stored(), canDelete: true);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Delete')),
        isSemantics(
          label: 'Delete',
          tooltip: '',
          isButton: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a stored file shows the icon for its type', (tester) async {
    await pumpRow(
      tester,
      PersistedUpload(
        filename: 'figures.csv',
        url: Uri.parse('https://example.com/figures.csv'),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.table_chart_outlined));
    final scheme =
        Theme.of(tester.element(find.byType(UploadEntryRow))).colorScheme;
    expect(icon.color, scheme.onSurfaceVariant,
        reason: 'a stored file is not a success to report');
  });
}
