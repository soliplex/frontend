import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/ui/assistant_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

Widget _section(
  WorkdirFilesStatus status, {
  Future<DownloadOutcome> Function(WorkdirFile file)? onDownload,
  VoidCallback? onRetry,
}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: AssistantFilesSection(
          status: status,
          onDownload: onDownload ?? (_) async => DownloadOutcome.success,
          onFetchBytes: (_) async => Uint8List(0),
          onRetry: onRetry ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('Loading renders nothing', (tester) async {
    await tester.pumpWidget(_section(const WorkdirFilesLoading()));

    expect(find.text('FROM THE ASSISTANT'), findsNothing);
  });

  testWidgets('Loaded with no files renders nothing', (tester) async {
    await tester.pumpWidget(_section(const WorkdirFilesLoaded([])));

    expect(find.text('FROM THE ASSISTANT'), findsNothing);
  });

  testWidgets('Loaded lists the files and badges only the unseen ones',
      (tester) async {
    await tester.pumpWidget(_section(
      WorkdirFilesLoaded(
        [_file('a.csv'), _file('b.png')],
        unseen: const {'b.png'},
      ),
    ));

    expect(find.text('FROM THE ASSISTANT'), findsOneWidget);
    expect(find.text('a.csv'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('b.png'),
          matching: find.byType(WorkdirFileRow),
        ),
        matching: find.text('New'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a row download icon downloads that file',
      (tester) async {
    final downloaded = <WorkdirFile>[];
    await tester.pumpWidget(_section(
      WorkdirFilesLoaded([_file('a.csv'), _file('b.png')]),
      onDownload: (file) async {
        downloaded.add(file);
        return DownloadOutcome.success;
      },
    ));

    await tester.tap(find.byIcon(Icons.download_outlined).last);
    await tester.pump();

    expect(downloaded, [_file('b.png')]);
  });

  testWidgets('tapping a previewable row opens a preview over every file',
      (tester) async {
    await tester.pumpWidget(_section(
      WorkdirFilesLoaded([_file('a.csv'), _file('b.png')]),
    ));

    await tester.tap(find.text('b.png'));
    await tester.pump();

    final page =
        tester.widget<WorkdirPreviewPage>(find.byType(WorkdirPreviewPage));
    expect(page.files.length, 2);
    expect(page.initialIndex, 1);
  });

  testWidgets('Failed shows the message and Retry runs onRetry',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(_section(
      const WorkdirFilesFailed('boom'),
      onRetry: () => retries++,
    ));

    expect(find.text('FROM THE ASSISTANT'), findsOneWidget);
    expect(find.textContaining("Couldn't load files"), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));

    expect(retries, 1);
  });

  testWidgets('Failed explains the failure without rendering the raw message',
      (tester) async {
    const error = NetworkException(message: 'down');
    await tester.pumpWidget(_section(const WorkdirFilesFailed(error)));

    expect(find.textContaining(workdirErrorMessage(error)), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server."), findsOneWidget);
    expect(find.textContaining('down'), findsNothing);
  });

  testWidgets('Failed while retrying swaps Retry for a spinner',
      (tester) async {
    await tester.pumpWidget(_section(
      const WorkdirFilesFailed('boom', retrying: true),
    ));

    expect(find.text('FROM THE ASSISTANT'), findsOneWidget);
    expect(find.textContaining("Couldn't load files"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Retry'), findsNothing);
  });

  testWidgets('the error row keeps its height while a retry is in flight',
      (tester) async {
    Widget row({required bool isRetrying}) => MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: Scaffold(
            body: WorkdirErrorRow(onRetry: () {}, isRetrying: isRetrying),
          ),
        );

    await tester.pumpWidget(row(isRetrying: false));
    final idleHeight = tester.getSize(find.byType(WorkdirErrorRow)).height;
    await tester.pumpWidget(row(isRetrying: true));
    final retryingHeight = tester.getSize(find.byType(WorkdirErrorRow)).height;

    expect(retryingHeight, idleHeight);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
