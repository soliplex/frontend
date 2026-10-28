import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/upload_entry_row.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

void main() {
  final cancelled = <String>[];
  final dismissed = <String>[];

  setUp(() {
    cancelled.clear();
    dismissed.clear();
  });

  Future<void> pumpRow(WidgetTester tester, DisplayUpload entry) =>
      tester.pumpWidget(
        MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: Scaffold(
            body: UploadEntryRow(
              entry: entry,
              onCancel: cancelled.add,
              onDismiss: dismissed.add,
            ),
          ),
        ),
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
  });
}
