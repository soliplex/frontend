import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

import '../../../helpers/file_name_finder.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

Widget _section(
  WorkdirFilesStatus status, {
  Future<DownloadOutcome> Function(WorkdirFile file)? onDownload,
}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: WorkspaceFilesSection(
          status: status,
          onDownload: onDownload ?? (_) async => DownloadOutcome.success,
          onFetchBytes: (_) async => Uint8List(0),
          onRetry: () {},
          folderToggles: const {},
          onFolderToggled: (_, {required expanded}) {},
        ),
      ),
    );

/// A loaded section whose folder toggles are held the way the room holds
/// them, so a tap on a folder takes effect.
Widget _grouped(
  List<String> paths, {
  Map<String, bool> toggles = const {},
}) {
  var held = toggles;
  return MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => WorkspaceFilesSection(
            status: WorkdirFilesLoaded([for (final p in paths) _file(p)]),
            onDownload: (_) async => DownloadOutcome.success,
            onFetchBytes: (_) async => Uint8List.fromList([104, 105]),
            onRetry: () {},
            folderToggles: held,
            onFolderToggled: (folder, {required expanded}) =>
                setState(() => held = {...held, folder: expanded}),
          ),
        ),
      ),
    ),
  );
}

void main() {
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

  testWidgets('Failed explains the failure without rendering the raw message',
      (tester) async {
    const error = NetworkException(message: 'down');
    await tester.pumpWidget(_section(const WorkdirFilesFailed(error)));

    expect(find.textContaining("Couldn't reach the server."), findsOneWidget);
    expect(find.textContaining('down'), findsNothing);
  });

  testWidgets('Failed while retrying swaps Retry for a spinner',
      (tester) async {
    await tester.pumpWidget(_section(
      const WorkdirFilesFailed('boom', retrying: true),
    ));

    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(find.textContaining("Couldn't load files"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Retry'), findsNothing);
    expect(find.byTooltip('Retrying'), findsOneWidget,
        reason: 'the disabled button still names itself to screen readers');
  });

  testWidgets('the error row keeps its height while a retry is in flight',
      (tester) async {
    Widget row({required bool isRetrying}) => MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: Scaffold(
            body: WorkdirErrorRow(
              onRetry: () {},
              isRetrying: isRetrying,
              reason: 'Something went wrong.',
            ),
          ),
        );

    await tester.pumpWidget(row(isRetrying: false));
    final idleHeight = tester.getSize(find.byType(WorkdirErrorRow)).height;
    await tester.pumpWidget(row(isRetrying: true));
    final retryingHeight = tester.getSize(find.byType(WorkdirErrorRow)).height;

    expect(retryingHeight, idleHeight);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  group('folders', () {
    Finder folder(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(InkWell));

    testWidgets('root files come before the folders', (tester) async {
      await tester.pumpWidget(_grouped(['crm_app/README.md', 'notes.txt']));

      expect(
        tester.getTopLeft(findFileName('notes.txt')).dy,
        lessThan(tester.getTopLeft(find.text('crm_app')).dy),
      );
    });

    testWidgets('a folder counts every file below it, and no root file',
        (tester) async {
      await tester.pumpWidget(
        _grouped(['notes.txt', 'reports/a.csv', 'reports/sub/b.csv']),
      );

      expect(find.text('2 files'), findsOneWidget);
    });

    testWidgets('a folder says its count beside its name', (tester) async {
      // Not in the trailing column, which holds only the file rows' actions:
      // a number there sits out of line with their icons and reads as one.
      await tester.pumpWidget(_grouped(['reports/a.csv', 'reports/b.csv']));

      final name = tester.getRect(find.text('reports'));
      final count = tester.getRect(find.text('2 files'));
      expect(count.left - name.right, lessThanOrEqualTo(SoliplexSpacing.s2));
    });

    testWidgets('tapping a folder closes it, and tapping again opens it',
        (tester) async {
      await tester.pumpWidget(_grouped(['reports/a.csv']));
      expect(findFileName('a.csv'), findsOneWidget);

      await tester.tap(folder('reports'));
      await tester.pump();
      expect(findFileName('a.csv'), findsNothing);

      await tester.tap(folder('reports'));
      await tester.pump();
      expect(findFileName('a.csv'), findsOneWidget);
    });

    testWidgets('a folder shows an open icon while open, a closed one shut',
        (tester) async {
      await tester.pumpWidget(_grouped(['reports/a.csv']));
      Finder icon(IconData data) =>
          find.descendant(of: folder('reports'), matching: find.byIcon(data));
      expect(icon(Icons.folder_open_outlined), findsOneWidget);

      await tester.tap(folder('reports'));
      await tester.pump();

      expect(icon(Icons.folder_outlined), findsOneWidget);
      expect(icon(Icons.folder_open_outlined), findsNothing);
    });

    testWidgets('.git and __pycache__ start closed', (tester) async {
      await tester.pumpWidget(_grouped(
        ['.git/HEAD', '__pycache__/x.pyc', 'reports/a.csv'],
      ));

      expect(findFileName('HEAD'), findsNothing);
      expect(findFileName('x.pyc'), findsNothing);
      expect(findFileName('a.csv'), findsOneWidget);
    });

    testWidgets('a toggle wins over a folder that starts closed',
        (tester) async {
      await tester.pumpWidget(_grouped(['.git/HEAD'], toggles: {'.git': true}));

      expect(findFileName('HEAD'), findsOneWidget);
    });

    testWidgets('a screen reader hears a folder, its count and its state',
        (tester) async {
      await tester.pumpWidget(
        _grouped(['logs/x.log', 'reports/a.csv', 'reports/b.csv']),
      );

      expect(
        tester.getSemantics(folder('logs')).getSemanticsData().label,
        'logs, 1 file',
      );
      var data = tester.getSemantics(folder('reports')).getSemanticsData();
      expect(data.label, 'reports, 2 files');
      expect(data.flagsCollection.isExpanded.toBoolOrNull(), isTrue);

      await tester.tap(folder('reports'));
      await tester.pump();

      data = tester.getSemantics(folder('reports')).getSemanticsData();
      expect(data.flagsCollection.isExpanded.toBoolOrNull(), isFalse);
    });

    testWidgets('the preview pages through the tapped file\'s folder only',
        (tester) async {
      await tester.pumpWidget(_grouped(
        ['a.txt', 'b.txt', 'reports/c.txt', 'reports/d.txt', 'reports/e.txt'],
      ));

      await tester.tap(findFileName('d.txt'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 3 · reports'), findsOneWidget);
    });

    testWidgets('the preview pages through the root files only',
        (tester) async {
      await tester.pumpWidget(_grouped(['a.txt', 'b.txt', 'reports/c.txt']));

      await tester.tap(findFileName('b.txt'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
    });
  });
}
