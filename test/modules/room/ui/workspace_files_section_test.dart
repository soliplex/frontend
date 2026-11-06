import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';
import 'package:soliplex_frontend/src/shared/local_time_format.dart';

import '../../../helpers/file_name_finder.dart';
import '../../../helpers/preview_title_finder.dart';
import '../../../helpers/test_downloads.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

Widget _host(Widget section) => MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: section)),
    );

WorkspaceFilesSection _sorted(
  List<String> paths,
  FileSort sort,
) =>
    WorkspaceFilesSection(
      status: WorkdirFilesLoaded([for (final p in paths) _file(p)]),
      sort: sort,
      downloads: testDownloads(),
      onFetchBytes: (_) async => Uint8List.fromList([104, 105]),
      onRetry: () {},
      folderToggles: const {},
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
          downloads: testDownloads(onDownload),
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
  final downloads = testDownloads();
  return MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => WorkspaceFilesSection(
            status: WorkdirFilesLoaded(files),
            sort: FileSort.foldersAToZ,
            downloads: downloads,
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
        return const DownloadSaved();
      },
    ));

    await tester.tap(find.byIcon(Icons.download_outlined).last);
    await tester.pump();

    expect(downloaded, [_file('b.png')]);
    await tester.pump(const Duration(seconds: 2));
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
    // On a desktop, where the button is as tall as its glyph: a touch one
    // pads to 48 px whatever the glyph, hiding a spinner of another size.
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  group('folders', () {
    Finder folder(String name) =>
        find.ancestor(of: findFolderPath(name), matching: find.byType(InkWell));

    testWidgets('root files come before the folders', (tester) async {
      await tester.pumpWidget(_grouped(['crm_app/README.md', 'notes.txt']));

      expect(
        tester.getTopLeft(findFileName('notes.txt')).dy,
        lessThan(tester.getTopLeft(findFolderPath('crm_app')).dy),
      );
    });

    testWidgets('a folder says its count under its name', (tester) async {
      // Not in the trailing column, which holds the rows' actions and a
      // folder's chevron: a number there sits out of line with their icons
      // and reads as an action. Under the name, as a file row's time and
      // size are.
      await tester.pumpWidget(_grouped(['reports/a.csv', 'reports/b.csv']));

      final name = tester.getRect(findFolderPath('reports'));
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

    testWidgets(
        'a narrow folder row cuts the middle of the name and keeps the count',
        (tester) async {
      tester.view.physicalSize = const Size(200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const folder = 'quarterly_financial_reports_archive';
      await tester.pumpWidget(_grouped(['$folder/a.csv', '$folder/b.csv']));

      bool isCut(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .didExceedMaxLines;
      final count = tester.renderObject<RenderParagraph>(find.text('2 files'));
      expect(isCut('quarterly_financial_reports_a'), isTrue);
      expect(isCut('rchive'), isFalse);
      expect(
        count.size.width,
        greaterThanOrEqualTo(count.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('a narrow merged chain keeps its last folder', (tester) async {
      tester.view.physicalSize = const Size(200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _grouped(['raw_material_archive/2023/a.csv', 'notes.txt']),
      );

      bool isCut(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .didExceedMaxLines;
      expect(isCut('raw_material_archive'), isTrue);
      expect(isCut('/2023'), isFalse);
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

    group('nested', () {
      testWidgets('a nested folder starts closed and opens on a tap',
          (tester) async {
        await tester.pumpWidget(_grouped(['src/main.py', 'src/lib/util.py']));
        expect(findFileName('main.py'), findsOneWidget);
        expect(find.text('lib'), findsOneWidget);
        expect(findFileName('util.py'), findsNothing);

        await tester.tap(folder('lib'));
        await tester.pump();

        expect(findFileName('util.py'), findsOneWidget);
      });

      testWidgets('a chain of single folders shows as one row', (tester) async {
        await tester.pumpWidget(_grouped(['raw/archive/2023/a.csv']));

        expect(findFolderPath('raw/archive/2023'), findsOneWidget);
        expect(findFileName('a.csv'), findsOneWidget,
            reason: 'the chain is a top-level row, so it starts open');
      });

      testWidgets('a file shows no directory after its name', (tester) async {
        await tester.pumpWidget(_grouped(
          ['src/a.py', 'src/lib/util.py'],
          toggles: {'src/lib': true},
        ));

        expect(findFileName('util.py'), findsOneWidget);
        expect(find.textContaining('/'), findsNothing);
      });

      testWidgets('a screen reader hears a nested folder by its full path',
          (tester) async {
        await tester.pumpWidget(_grouped(['src/a.py', 'src/lib/util.py']));

        expect(
          tester.getSemantics(folder('lib')).getSemanticsData().label,
          'src/lib, 1 file',
        );
      });

      testWidgets("a folder's tooltip carries its full path", (tester) async {
        await tester.pumpWidget(_grouped(['src/a.py', 'src/lib/util.py']));

        expect(find.byTooltip('src/lib'), findsOneWidget);
      });

      group('deeper than four levels', () {
        // Every folder holds a file, so no chain merges.
        const listing = [
          'a/xa',
          'a/b/xb',
          'a/b/c/xc',
          'a/b/c/d/xd',
          'a/b/c/d/e/xe',
          'a/b/c/d/e/f/xf',
          'a/b/c/d/e/f/g/xg',
        ];
        const open = {
          'a/b': true,
          'a/b/c': true,
          'a/b/c/d': true,
          'a/b/c/d/e': true,
          'a/b/c/d/e/f': true,
          'a/b/c/d/e/f/g': true,
        };
        double indentOf(WidgetTester tester, String name) =>
            tester.getTopLeft(find.text(name)).dx -
            tester.getTopLeft(find.text('a')).dx;

        testWidgets('each level indents, by less past four', (tester) async {
          await tester.pumpWidget(_grouped(listing, toggles: open));

          for (final (level, name) in ['b', 'c', 'd', 'e'].indexed) {
            expect(indentOf(tester, name), (level + 1) * SoliplexSpacing.s4,
                reason: name);
          }
          expect(indentOf(tester, 'f'),
              4 * SoliplexSpacing.s4 + SoliplexSpacing.s1);
          expect(indentOf(tester, 'g'),
              4 * SoliplexSpacing.s4 + 2 * SoliplexSpacing.s1);
        });

        testWidgets('a file past four levels sits inside its folder',
            (tester) async {
          await tester.pumpWidget(_grouped(listing, toggles: open));

          expect(
            tester.getTopLeft(findFileName('xg')).dx -
                tester.getTopLeft(find.text('g')).dx,
            SoliplexSpacing.s1,
          );
        });

        testWidgets("a folder past the indent shows its parent's path",
            (tester) async {
          await tester.pumpWidget(_grouped(listing, toggles: open));

          expect(findFolderPath('a/b/c/d/e'), findsOneWidget);
          expect(find.text('/e/'), findsOneWidget,
              reason: 'the parent path keeps its last folder whole');
          expect(findFolderPath('a/b/c/d'), findsNothing,
              reason: 'e still has an indent of its own');
        });
      });
    });

    testWidgets('the preview pages through the tapped file\'s folder only',
        (tester) async {
      await tester.pumpWidget(_grouped([
        'a.txt',
        'b.txt',
        'reports/c.txt',
        'reports/d.txt',
        'reports/e.txt',
        'reports/sub/f.txt',
      ], toggles: {
        'reports/sub': true,
      }));

      await tester.tap(findFileName('d.txt'));
      await tester.pumpAndSettle();

      expect(findPreviewTitle('2 / 3 · reports/'), findsOneWidget);
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
  });

  group('flat options', () {
    const listing = [
      'src-b/another/dir/file-b',
      'a.txt',
      'src-a/main.py',
    ];

    testWidgets('a flat option lists every file with its directory',
        (tester) async {
      await tester.pumpWidget(_host(_sorted(listing, FileSort.nameAToZ)));

      // No folder rows: every file is its own row.
      expect(find.textContaining('files'), findsNothing);
      expect(findFolderPath('src-b/another/dir'), findsOneWidget);
      expect(
        tester.getTopLeft(findFileName('a.txt')).dy,
        lessThan(tester.getTopLeft(findFileName('file-b')).dy),
      );
    });
  });
}
