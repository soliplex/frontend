import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';
import 'package:soliplex_frontend/src/shared/local_time_format.dart';

import '../../../helpers/file_name_finder.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

Widget _host(Widget section) => MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: section)),
    );

WorkspaceFilesSection _sorted(
  List<String> paths,
  FileSort sort, {
  Map<String, bool> toggles = const {},
}) =>
    WorkspaceFilesSection(
      status: WorkdirFilesLoaded([for (final p in paths) _file(p)]),
      sort: sort,
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List.fromList([104, 105]),
      onRetry: () {},
      folderToggles: toggles,
      onFolderToggled: (_, {required expanded}) {},
    );

Widget _section(
  WorkdirFilesStatus status, {
  Future<DownloadOutcome> Function(WorkdirFile file)? onDownload,
}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: WorkspaceFilesSection(
          status: status,
          sort: FileSort.foldersAToZ,
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
}) =>
    _groupedFiles([for (final p in paths) _file(p)], toggles: toggles);

Widget _groupedFiles(
  List<WorkdirFile> files, {
  Map<String, bool> toggles = const {},
}) {
  var held = toggles;
  return MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => WorkspaceFilesSection(
            status: WorkdirFilesLoaded(files),
            sort: FileSort.foldersAToZ,
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

  testWidgets('Retrying is still a button to a screen reader', (tester) async {
    // The spinner's loading-spinner role must not merge into the button,
    // where the web would announce it in place of the button role.
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_section(
        const WorkdirFilesFailed('boom', retrying: true),
      ));

      final data =
          tester.getSemantics(find.byTooltip('Retrying')).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.role, SemanticsRole.none);
    } finally {
      semantics.dispose();
    }
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

    testWidgets('a folder says its count under its name', (tester) async {
      // Not in the trailing column, which holds the rows' actions and a
      // folder's chevron: a number there sits out of line with their icons
      // and reads as an action. Under the name, as a file row's time and
      // size are.
      await tester.pumpWidget(_grouped(['reports/a.csv', 'reports/b.csv']));

      final name = tester.getRect(find.text('reports'));
      final count = tester.getRect(find.text('2 files'));
      expect(count.top, greaterThanOrEqualTo(name.bottom - 1));
      expect(count.left, name.left);
    });

    group('latest change inside', () {
      final now = DateTime.now();
      WorkdirFile at(String path, Duration ago) => WorkdirFile(
            filename: path,
            url: Uri.parse('https://example.test/$path'),
            modifiedAt: now.subtract(ago),
          );

      testWidgets('shows when the newest file at any depth changed',
          (tester) async {
        // The newest is neither first nor last, so only the newest wins.
        await tester.pumpWidget(_groupedFiles([
          at('reports/a.csv', const Duration(days: 2)),
          at('reports/sub/b.csv', const Duration(hours: 3, minutes: 1)),
          at('reports/c.csv', const Duration(days: 4)),
        ]));

        expect(find.text('3 files · 3h ago'), findsOneWidget);
      });

      testWidgets('shows only the count when no file has a time',
          (tester) async {
        await tester.pumpWidget(_grouped(['reports/a.csv']));

        expect(find.text('1 file'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Tooltip && w.message!.startsWith('Latest change'),
          ),
          findsNothing,
        );
      });

      testWidgets("the exact time shows on hover, in the viewer's zone",
          (tester) async {
        // UTC, as the server sends it. Only a runner outside UTC can catch
        // a time shown in UTC.
        final modifiedAt = DateTime.utc(2026, 11, 5, 15, 42);
        await tester.pumpWidget(_groupedFiles([
          WorkdirFile(
            filename: 'reports/a.csv',
            url: Uri.parse('https://example.test/reports/a.csv'),
            modifiedAt: modifiedAt,
          ),
        ]));

        expect(
          find.byTooltip(
            'Latest change inside: ${formatDateAndTime(modifiedAt.toLocal())}',
          ),
          findsOneWidget,
        );
      });

      testWidgets('a screen reader hears it after the count', (tester) async {
        await tester.pumpWidget(_groupedFiles([
          at('reports/a.csv', const Duration(hours: 3, minutes: 1)),
        ]));

        expect(
          tester.getSemantics(folder('reports')).getSemanticsData().label,
          'reports, 1 file, latest change 3 hours ago',
        );
      });
    });

    testWidgets('a narrow folder row shortens the name and keeps the count',
        (tester) async {
      tester.view.physicalSize = const Size(200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const folder = 'quarterly_financial_reports_archive';
      await tester.pumpWidget(_grouped(['$folder/a.csv', '$folder/b.csv']));

      final name = tester.renderObject<RenderParagraph>(find.text(folder));
      final count = tester.renderObject<RenderParagraph>(find.text('2 files'));
      expect(name.didExceedMaxLines, isTrue);
      expect(
        count.size.width,
        greaterThanOrEqualTo(count.getMaxIntrinsicWidth(double.infinity)),
      );
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

    testWidgets("a folder's chevron sits in the files' download column",
        (tester) async {
      await tester.pumpWidget(_grouped(['notes.txt', 'reports/a.csv']));
      final download = find
          .descendant(
            of: find.ancestor(
              of: findFileName('notes.txt'),
              matching: find.byType(FileListRow),
            ),
            matching: find.byType(FileRowAction),
          )
          .last;

      expect(
        tester.getCenter(find.byIcon(Icons.expand_less)).dx,
        tester.getCenter(download).dx,
      );
    });

    testWidgets("a folder's chevron points up while open, down while shut",
        (tester) async {
      await tester.pumpWidget(_grouped(['reports/a.csv']));
      Finder icon(IconData data) =>
          find.descendant(of: folder('reports'), matching: find.byIcon(data));
      expect(icon(Icons.expand_less), findsOneWidget);

      await tester.tap(folder('reports'));
      await tester.pump();

      expect(icon(Icons.expand_more), findsOneWidget);
      expect(icon(Icons.expand_less), findsNothing);
    });

    testWidgets("a folder's icon lines up with the root files' icons",
        (tester) async {
      await tester.pumpWidget(_grouped(['notes.txt', 'reports/a.csv']));
      final fileIcon = find
          .descendant(
            of: find.ancestor(
              of: findFileName('notes.txt'),
              matching: find.byType(FileListRow),
            ),
            matching: find.byType(Icon),
          )
          .first;

      expect(
        tester.getTopLeft(find.byIcon(Icons.folder_open_outlined)).dx,
        tester.getTopLeft(fileIcon).dx,
      );
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

    testWidgets("a tooling folder's name is muted", (tester) async {
      await tester.pumpWidget(
        _grouped(['.git/HEAD', '__pycache__/x.pyc', 'reports/a.csv']),
      );
      final muted = Theme.of(tester.element(find.text('reports')))
          .colorScheme
          .onSurfaceVariant;
      Color? color(String name) =>
          tester.widget<Text>(find.text(name)).style?.color;

      expect(color('.git'), muted);
      expect(color('__pycache__'), muted);
      expect(color('reports'), isNot(muted));
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

      expect(find.text('2 / 3 · reports/'), findsOneWidget);
    });

    testWidgets('the preview pages through the root files only',
        (tester) async {
      await tester.pumpWidget(_grouped(['a.txt', 'b.txt', 'reports/c.txt']));

      await tester.tap(findFileName('b.txt'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
    });
  });

  group('Folders, Z to A', () {
    testWidgets('reverses the root files and the folders', (tester) async {
      await tester.pumpWidget(_host(_sorted(
        ['a.txt', 'b.txt', 'src-a/x.py', 'src-b/y.py'],
        FileSort.foldersZToA,
      )));

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      expect(top(findFileName('b.txt')), lessThan(top(findFileName('a.txt'))));
      expect(top(find.text('src-b')), lessThan(top(find.text('src-a'))));
    });

    testWidgets('keeps a download in progress inside a folder', (tester) async {
      final download = Completer<DownloadOutcome>();
      Widget section(FileSort sort) => _host(WorkspaceFilesSection(
            status: WorkdirFilesLoaded([_file('a/x.pdf'), _file('z/y.pdf')]),
            sort: sort,
            onDownload: (_) => download.future,
            onFetchBytes: (_) async => Uint8List(0),
            onRetry: () {},
            folderToggles: const {},
            onFolderToggled: (_, {required expanded}) {},
          ));
      await tester.pumpWidget(section(FileSort.foldersAToZ));
      await tester.tap(find.byIcon(Icons.download_outlined).first);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(section(FileSort.foldersZToA));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      download.complete(DownloadOutcome.success);
      // Past the success tick's revert timer.
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('flat options', () {
    const listing = [
      'src-b/another/dir/file-b',
      '.git/HEAD',
      'a.txt',
      'src-a/main.py',
    ];

    testWidgets(
        'a flat option lists every file with its directory and tooling last',
        (tester) async {
      await tester.pumpWidget(_host(_sorted(listing, FileSort.nameAToZ)));

      // No folder rows: every file is its own row, `.git` included.
      expect(find.textContaining('files'), findsNothing);
      expect(find.text('src-b/another/dir/'), findsOneWidget);
      final head = tester.getTopLeft(findFileName('HEAD')).dy;
      for (final real in ['a.txt', 'file-b', 'main.py']) {
        expect(tester.getTopLeft(findFileName(real)).dy, lessThan(head),
            reason: '$real comes before tooling');
      }
      expect(
        tester.getTopLeft(findFileName('a.txt')).dy,
        lessThan(tester.getTopLeft(findFileName('file-b')).dy),
      );
    });

    testWidgets('a folder closed in Folders is closed after Name and back',
        (tester) async {
      const paths = ['src-b/file', 'a.txt'];
      const closed = {'src-b': false};

      await tester.pumpWidget(
          _host(_sorted(paths, FileSort.foldersAToZ, toggles: closed)));
      expect(findFileName('file'), findsNothing);

      await tester.pumpWidget(
          _host(_sorted(paths, FileSort.nameAToZ, toggles: closed)));
      expect(findFileName('file'), findsOneWidget);

      await tester.pumpWidget(
          _host(_sorted(paths, FileSort.foldersAToZ, toggles: closed)));
      expect(findFileName('file'), findsNothing);
    });

    testWidgets('preview from a flat list pages through the real files only',
        (tester) async {
      await tester.pumpWidget(_host(_sorted(
        ['a.txt', 'b.txt', '__pycache__/notes.txt'],
        FileSort.nameAToZ,
      )));

      await tester.tap(findFileName('b.txt'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
    });
  });
}
