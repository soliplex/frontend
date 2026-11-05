import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
import 'package:soliplex_frontend/src/shared/local_time_format.dart';

void main() {
  final fiveMinutesAgo =
      DateTime.now().subtract(const Duration(minutes: 5, seconds: 10));

  Future<void> pumpRow(
    WidgetTester tester, {
    DateTime? modifiedAt,
    int? sizeBytes,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: FileListRow(
                  leading: const Icon(Icons.description_outlined, size: 16),
                  content: const Text('report.pdf'),
                  details: DetailsLine.file(
                    modifiedAt: modifiedAt,
                    sizeBytes: sizeBytes,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('shows the time and the size on a line under the name',
      (tester) async {
    await pumpRow(tester, modifiedAt: fiveMinutesAgo, sizeBytes: 2458);

    expect(find.text('5m ago · 2.4 KB'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('5m ago · 2.4 KB')).dy,
      greaterThan(tester.getBottomLeft(find.text('report.pdf')).dy - 1),
    );
  });

  testWidgets('shows only the time when the size is unknown', (tester) async {
    await pumpRow(tester, modifiedAt: fiveMinutesAgo);

    expect(find.text('5m ago'), findsOneWidget);
  });

  testWidgets('shows only the size when the time is unknown', (tester) async {
    await pumpRow(tester, sizeBytes: 2458);

    expect(find.text('2.4 KB'), findsOneWidget);
  });

  testWidgets('a row with neither keeps the height of one line',
      (tester) async {
    await pumpRow(tester);

    expect(
      tester.getSize(find.byType(FileListRow)).height,
      FileRowAction.extent,
    );
  });

  testWidgets("the exact time shows on hover, in the viewer's zone",
      (tester) async {
    // UTC, as the server sends it. Only a runner outside UTC can catch a
    // time shown in UTC.
    final modifiedAt = DateTime.utc(2026, 11, 5, 15, 42);
    await pumpRow(tester, modifiedAt: modifiedAt);

    expect(
      find.byTooltip(formatDateAndTime(modifiedAt.toLocal())),
      findsOneWidget,
    );
  });

  testWidgets('a one-line row with actions centres its name on them',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: FileListRow(
                leading: const Icon(Icons.description_outlined, size: 16),
                content: const Text('report.pdf'),
                actions: [
                  FileRowAction(
                    icon: Icons.download_outlined,
                    tooltip: 'Download',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getCenter(find.text('report.pdf')).dy,
      tester.getCenter(find.byIcon(Icons.download_outlined)).dy,
    );
  });

  testWidgets('a screen reader hears the time and the size in words',
      (tester) async {
    final semantics = tester.ensureSemantics();
    // Disposed before the test ends, which a tear-down runs too late for.
    try {
      await pumpRow(tester, modifiedAt: fiveMinutesAgo, sizeBytes: 2458);

      expect(
        find.bySemanticsLabel('modified 5 minutes ago, 2.4 kilobytes'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
