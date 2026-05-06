import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart';

WorkdirFile _file(String name) => WorkdirFile(filename: name);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders each filename when fetch returns a non-empty list',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf'), _file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
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
      onDownload: (_, __) async => DownloadOutcome.success,
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
      onDownload: (_, __) async => DownloadOutcome.success,
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
      onDownload: (_, __) async => DownloadOutcome.success,
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
        return DownloadOutcome.success;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(gotRunId, 'run-42');
    expect(gotFile, same(file));
  });

  testWidgets('shows check icon briefly on success and reverts after 2s',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) async => DownloadOutcome.success,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsNothing);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('shows error icon briefly on failed and reverts after 2s',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) async => DownloadOutcome.failed,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('cancellation reverts to idle without any feedback swap',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) async => DownloadOutcome.cancelled,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('a throwing onDownload still flips to the error icon',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) async => throw Exception('boom'),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('second tap during an in-flight download is a no-op',
      (tester) async {
    final completer = Completer<DownloadOutcome>();
    var calls = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) {
        calls++;
        return completer.future;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(calls, 1);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(calls, 1);

    completer.complete(DownloadOutcome.success);
    await tester.pumpAndSettle();
  });

  testWidgets('second tap during feedback window is a no-op', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('report.pdf')],
      onDownload: (_, __) async {
        calls++;
        return DownloadOutcome.success;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(calls, 1);

    // Try tapping the (now check) icon — should not fire again.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(calls, 1);
  });
}
