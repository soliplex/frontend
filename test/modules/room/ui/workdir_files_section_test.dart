import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.com/$name'));

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders each filename when fetch returns a non-empty list',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf'), _file('plot.png')],
      onDownload: (_, __) async {},
    )));
    await tester.pump();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('plot.png'), findsOneWidget);
  });

  testWidgets('collapses to nothing when fetch returns an empty list',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => const [],
      onDownload: (_, __) async {},
    )));
    await tester.pump();

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('shows retry row when fetch throws an unexpected error',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => throw Exception('boom'),
      onDownload: (_, __) async {},
    )));
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('tapping retry re-invokes fetchFiles and clears the error',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async {
        calls++;
        if (calls == 1) throw Exception('boom');
        return [_file('report.pdf')];
      },
      onDownload: (_, __) async {},
    )));
    await tester.pump();
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('tapping a file row invokes onDownload with (runId, file)',
      (tester) async {
    String? gotRunId;
    WorkdirFile? gotFile;

    final file = _file('report.pdf');
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-42',
      fetchFiles: (_) async => [file],
      onDownload: (runId, f) async {
        gotRunId = runId;
        gotFile = f;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(gotRunId, 'run-42');
    expect(gotFile, same(file));
  });
}
