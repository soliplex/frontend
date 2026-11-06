import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_list_row.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

import '../../../helpers/file_name_finder.dart';
import '../../../helpers/preview_title_finder.dart';
import '../../../helpers/test_downloads.dart';

/// Minimal 1x1 transparent PNG so [Image.memory] can decode in tests.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

final Uint8List _htmlBytes =
    Uint8List.fromList('<html><body>not an image</body></html>'.codeUnits);

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

// The preview's own Download button, which shares its icons with the title
// bar's download action.
Finder _inButton(Finder f) => find.descendant(
      of: find.byType(SoliplexButton),
      matching: f,
    );

// The list underneath a preview still shows each row's name, and a short
// name's row paints it whole as its kept end, so an unqualified
// find.text('b.md') can hit two widgets. Scope finders to the preview page
// where it matters.
Finder _inPreview(Finder f) => find.descendant(
      of: find.byType(WorkdirPreviewPage),
      matching: f,
    );

/// A [WorkspaceFilesSection] whose folders keep their default state: these
/// tests are about the rows and the preview, not about opening folders.
///
/// Its downloads save through [onDownload], unless [downloads] is given: a
/// test that pumps the section again passes the same downloads each time, as
/// the room's download registry does.
WorkspaceFilesSection _workspace({
  required WorkdirFilesStatus status,
  required VoidCallback onRetry,
  required Future<Uint8List> Function(WorkdirFile file) onFetchBytes,
  Future<DownloadOutcome> Function(WorkdirFile file)? onDownload,
  FileDownloads? downloads,
  FileSort sort = FileSort.foldersAToZ,
}) =>
    WorkspaceFilesSection(
      status: status,
      sort: sort,
      onRetry: onRetry,
      downloads: downloads ?? testDownloads(onDownload),
      onFetchBytes: onFetchBytes,
      folderToggles: const {},
      onFolderToggled: (_, {required expanded}) {},
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  // Image previews share Flutter's global imageCache; a partially-decoded
  // entry from one test will resurface as a "Codec failed" error in the
  // next, masking real failures.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  testWidgets('a file row shows its time and size', (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([
        WorkdirFile(
          filename: 'notes.txt',
          url: Uri.parse('https://example.test/notes.txt'),
          modifiedAt:
              DateTime.now().subtract(const Duration(hours: 3, minutes: 1)),
          sizeBytes: 2458,
        ),
      ]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List(0),
    )));

    expect(find.text('3h ago · 2.4 KB'), findsOneWidget);
    expect(
      find.bySemanticsLabel('notes.txt\nmodified 3 hours ago, 2.4 kilobytes'),
      findsOneWidget,
    );
  });

  testWidgets("a tooling file's name is muted", (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      // A root `.git` file is a worktree's pointer: a tooling path that
      // shows as a row of its own.
      status: WorkdirFilesLoaded([_file('.git'), _file('notes.txt')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List(0),
    )));
    final muted = Theme.of(tester.element(findFileName('notes.txt')))
        .colorScheme
        .onSurfaceVariant;

    expect(tester.widget<FileName>(findFileName('.git')).style?.color, muted);
    expect(
      tester.widget<FileName>(findFileName('notes.txt')).style?.color,
      isNot(muted),
    );
  });

  testWidgets('renders each filename', (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf'), _file('plot.png')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => DownloadOutcome.success,
    )));
    await tester.pump();

    expect(findFileName('report.pdf'), findsOneWidget);
    expect(findFileName('plot.png'), findsOneWidget);
  });

  testWidgets('shows check icon briefly on success and reverts after 2s',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => DownloadOutcome.success,
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
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => DownloadOutcome.failed,
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
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => DownloadOutcome.cancelled,
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
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => throw Exception('boom'),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      "a row's download icon is primary, and its failure the error "
      'colour', (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async => DownloadOutcome.failed,
    )));
    await tester.pump();
    final colors =
        Theme.of(tester.element(find.byType(WorkdirFileRow))).colorScheme;
    Color? colorOf(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color;

    expect(colorOf(Icons.download_outlined), colors.primary);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(colorOf(Icons.error_outline), colors.error);
    await tester.pump(const Duration(seconds: 2));
  });

  group('a download under way stays with its file', () {
    // It is kept by the file's path, so it must follow the file, not the
    // position the file happens to hold in the list.
    Future<void> pumpFiles(
      WidgetTester tester,
      List<WorkdirFile> files,
      FileDownloads downloads,
    ) =>
        tester.pumpWidget(_wrap(_workspace(
          status: WorkdirFilesLoaded(files),
          onRetry: () {},
          onFetchBytes: (_) async => _tinyPng,
          downloads: downloads,
        )));

    Finder rowOf(String name) => find.ancestor(
          of: find.bySemanticsLabel(name),
          matching: find.byType(WorkdirFileRow),
        );

    testWidgets('when a file sorting before it appears', (tester) async {
      final download = Completer<DownloadOutcome>();
      final downloads = testDownloads((_) => download.future);
      await pumpFiles(tester, [_file('b.pdf')], downloads);
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();

      await pumpFiles(tester, [_file('a.pdf'), _file('b.pdf')], downloads);

      expect(
        find.descendant(
          of: rowOf('b.pdf'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowOf('a.pdf'),
          matching: find.byIcon(Icons.download_outlined),
        ),
        findsOneWidget,
      );

      download.complete(DownloadOutcome.success);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('a download under way spins in place of its button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final completer = Completer<DownloadOutcome>();
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('report.pdf')]),
        onRetry: () {},
        onFetchBytes: (_) async => _tinyPng,
        onDownload: (_) => completer.future,
      )));
      await tester.pump();
      final button = tester.getRect(find.byIcon(Icons.download_outlined));

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();

      expect(find.byIcon(Icons.download_outlined), findsNothing);
      final ring = find.byType(CircularProgressIndicator);
      expect(tester.getRect(ring).center, button.center);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Downloading'))
            .getSemanticsData()
            .role,
        SemanticsRole.status,
      );

      completer.complete(DownloadOutcome.success);
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('preview eye icon shown only for previewable files',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png'), _file('report.pdf')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('tapping the eye opens the preview page and fetches bytes',
      (tester) async {
    var fetchCalls = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (file) async {
        fetchCalls++;
        expect(file.filename, 'plot.png');
        return _tinyPng;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(fetchCalls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('preview close (X) dismisses the dialog', (tester) async {
    // Force dialog layout by giving the root a wide size.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('tapping rotate turns the previewed image a quarter turn',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 0);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
  });

  testWidgets('preview shows generic error + Retry when fetch fails',
      (tester) async {
    var fetchCalls = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async {
        fetchCalls++;
        if (fetchCalls == 1) throw Exception('boom-internal-leak-do-not-show');
        return _tinyPng;
      },
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load preview"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Raw exception text must not leak to the UI.
    expect(find.textContaining('boom-internal-leak-do-not-show'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fetchCalls, 2);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('preview shows "no longer exists" without Retry on 404',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => throw const NotFoundException(
        message: 'gone',
        resource: '/x',
      ),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text('File no longer exists'), findsOneWidget);
    // Retry on a permanent 404 just refetches the same 404 — no Retry.
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('.PNG (uppercase) is treated as previewable', (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('PLOT.PNG')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets(
      'empty bytes short-circuit to Download (not Retry), no InteractiveViewer',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List(0),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    // bytes.isEmpty short-circuits around _ImageOrFallback entirely —
    // no decode attempt, no Retry-forever even on a non-errorBuilder
    // path.
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets(
      'non-image bytes show Download (not Retry) as a peer of InteractiveViewer',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _htmlBytes,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets(
      'leading icon is image_outlined for previewable, file icon otherwise',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png'), _file('report.pdf')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets(
      'tapping a previewable row opens the preview and does not download',
      (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    // Tap the filename text — that's a non-icon part of the row body, so it
    // exercises the row InkWell rather than either trailing icon.
    await tester.tap(findFileName('plot.png'));
    await tester.pumpAndSettle();

    expect(downloads, 0);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
      "tapping a row that can't preview opens the preview at it and does not "
      'download', (tester) async {
    var downloads = 0;
    var fetches = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('a.md'), _file('report.pdf')]),
      onRetry: () {},
      onDownload: (_) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onFetchBytes: (_) async {
        fetches++;
        return Uint8List.fromList(utf8.encode('body'));
      },
    )));
    await tester.pump();

    await tester.tap(findFileName('report.pdf'));
    await tester.pumpAndSettle();

    expect(downloads, 0);
    expect(fetches, 0, reason: 'the preview opens at report.pdf, not a.md');
    expect(_inPreview(find.text("Can't preview this file")), findsOneWidget);
    expect(_inPreview(findPreviewTitle('2 / 2')), findsOneWidget);
  });

  testWidgets(
      "the download icon on a row that can't preview downloads, opening no "
      'preview', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onDownload: (_) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onFetchBytes: (_) async => Uint8List(0),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(downloads, 1);
    expect(find.byType(WorkdirPreviewPage), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      "a row's download under way shows in the file's preview, which starts "
      'no second one', (tester) async {
    final pending = Completer<DownloadOutcome>();
    var downloads = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onDownload: (_) {
        downloads++;
        return pending.future;
      },
      onFetchBytes: (_) async => Uint8List(0),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    await tester.tap(findFileName('report.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<SoliplexButton>(_inPreview(find.byType(SoliplexButton)))
          .isLoading,
      isTrue,
    );
    expect(_inPreview(find.byTooltip('Downloading')), findsOneWidget);
    await tester.tap(_inPreview(find.byTooltip('Downloading')),
        warnIfMissed: false);
    await tester.tap(_inPreview(find.byType(SoliplexButton)),
        warnIfMissed: false);
    expect(downloads, 1);

    pending.complete(DownloadOutcome.success);
    await tester.pump();
    expect(_inPreview(find.byTooltip('Saved')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'tapping the trailing download icon on a previewable row downloads',
      (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(downloads, 1);
    // The preview dialog/page should not have opened.
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('code file opens preview with a HighlightView code block',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('script.py')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async =>
          Uint8List.fromList(utf8.encode('print("hi")\n')),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    // The code-block builder hands the body to flutter_highlight's
    // HighlightView — proves dispatch landed on CodePreview, not text.
    expect(find.byType(HighlightView), findsOneWidget);
  });

  testWidgets('markdown file opens preview through the markdown renderer',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('NOTES.md')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async =>
          Uint8List.fromList(utf8.encode('# Heading\n\nbody')),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    // TextPreview wraps the content in MarkdownBody. Image/code paths
    // don't, so finding MarkdownBody proves dispatch landed on text.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(HighlightView), findsNothing);
  });

  testWidgets('json file is pretty-printed inside a HighlightView',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('data.json')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async =>
          Uint8List.fromList(utf8.encode('{"a":1,"b":[2,3]}')),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    final view = tester.widget<HighlightView>(find.byType(HighlightView));
    expect(view.language, 'json');
    // 2-space indent is the pretty-print contract — verifying it via the
    // raw source the highlighter receives.
    expect(view.source, contains('"a": 1'));
  });

  testWidgets('svg file opens preview with SvgPicture in InteractiveViewer',
      (tester) async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>';
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('chart.svg')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List.fromList(utf8.encode(svg)),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('bytes exactly at the 5 MB cap still preview (not too-large)',
      (tester) async {
    // The cap is a strict `>`. A regression to `>=` would silently
    // tip cap-sized files into the too-large state. Use a .png
    // filename so the body routes through Image.memory — invalid
    // bytes hit the fast errorBuilder fallback without exercising a
    // text/markdown decoder on 5 MB of zeros.
    final atCap = Uint8List(5 * 1024 * 1024);
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('boundary.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => atCap,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text('File is too large to preview'), findsNothing);
  });

  testWidgets('bytes over the 5 MB cap render the too-large placeholder',
      (tester) async {
    final overCap = Uint8List(5 * 1024 * 1024 + 1);
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('huge.log')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => overCap,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text('File is too large to preview'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    // The actual preview body never gets built — no decoder runs.
    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.byType(HighlightView), findsNothing);
  });

  testWidgets("a too-large file's Download saves it and shows the outcome",
      (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('huge.log')]),
      onRetry: () {},
      onDownload: (file) async {
        saved.add(file.filename);
        return DownloadOutcome.success;
      },
      onFetchBytes: (_) async => Uint8List(5 * 1024 * 1024 + 1),
    )));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SoliplexButton, 'Download'));
    await tester.pump();

    expect(saved, ['huge.log']);
    expect(find.widgetWithText(SoliplexButton, 'Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('pdf row is not previewable — no eye icon, generic file icon',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('paper.pdf')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
  });

  testWidgets('unknown extension row is not previewable — no eye icon',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('blob.xyz')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets('per-kind leading icons appear on previewable rows',
      (tester) async {
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([
        _file('script.py'),
        _file('data.json'),
        _file('table.csv'),
        _file('notes.md'),
      ]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.code), findsOneWidget);
    expect(find.byIcon(Icons.data_object), findsOneWidget);
    expect(find.byIcon(Icons.table_chart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
  });

  group("a row's download icon, while it can't download, does nothing", () {
    Future<Completer<DownloadOutcome>> startDownload(
      WidgetTester tester,
      List<int> calls,
    ) async {
      final download = Completer<DownloadOutcome>();
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('report.pdf')]),
        onRetry: () {},
        onFetchBytes: (_) async => _tinyPng,
        onDownload: (_) {
          calls.add(1);
          return download.future;
        },
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump();
      return download;
    }

    testWidgets('while it runs', (tester) async {
      final calls = <int>[];
      final download = await startDownload(tester, calls);

      await tester.tap(find.byType(FileRowActionProgress));
      await tester.pump();

      expect(find.byType(WorkdirPreviewPage), findsNothing);
      expect(calls, hasLength(1));
      download.complete(DownloadOutcome.success);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('while its outcome shows', (tester) async {
      final calls = <int>[];
      final download = await startDownload(tester, calls);
      download.complete(DownloadOutcome.success);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();

      expect(find.byType(WorkdirPreviewPage), findsNothing);
      expect(calls, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('multi-file pager', () {
    IconButton iconButtonWith(WidgetTester tester, IconData icon) {
      return tester.widget<IconButton>(
        find.descendant(
          of: find.byType(WorkdirPreviewPage),
          matching: find.widgetWithIcon(IconButton, icon),
        ),
      );
    }

    testWidgets('opens at the tapped file when multiple files exist',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([
          _file('a.png'),
          _file('b.md'),
          _file('c.json'),
        ]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (file) async => Uint8List.fromList(
          utf8.encode(file.filename == 'b.md' ? '# hi' : 'irrelevant'),
        ),
      )));
      await tester.pump();

      // Tap the eye icon on the markdown row (the middle of three).
      await tester.tap(find.byIcon(Icons.visibility_outlined).at(1));
      await tester.pumpAndSettle();

      // The title bar shows the tapped filename and "2 / 3" position.
      expect(_inPreview(findPreviewTitle('b.md')), findsOneWidget);
      expect(findPreviewTitle('2 / 3'), findsOneWidget);
    });

    testWidgets('next arrow advances; disabled at the last index',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(findPreviewTitle('1 / 2'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(WorkdirPreviewPage),
        matching: find.widgetWithIcon(IconButton, Icons.chevron_right),
      ));
      await tester.pumpAndSettle();
      expect(findPreviewTitle('2 / 2'), findsOneWidget);

      // At the last index, Next is disabled.
      expect(iconButtonWith(tester, Icons.chevron_right).onPressed, isNull);
    });

    testWidgets('prev arrow is disabled at the first index', (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      expect(iconButtonWith(tester, Icons.chevron_left).onPressed, isNull);
    });

    testWidgets('keyboard right arrow advances to the next file',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(findPreviewTitle('1 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(findPreviewTitle('2 / 2'), findsOneWidget);
      expect(_inPreview(findPreviewTitle('b.md')), findsOneWidget);
    });

    testWidgets('dots jump to the tapped index', (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([
          _file('a.md'),
          _file('b.md'),
          _file('c.md'),
        ]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(findPreviewTitle('1 / 3'), findsOneWidget);

      // Tap the third dot — InkResponses inside the preview's dots row
      // each carry the filename tooltip. The third one is at index 2.
      await tester.tap(find.descendant(
        of: find.byType(WorkdirPreviewPage),
        matching: find.byTooltip('c.md'),
      ));
      await tester.pumpAndSettle();

      expect(findPreviewTitle('3 / 3'), findsOneWidget);
    });

    testWidgets('dots are hidden when more than 12 files', (tester) async {
      final many = List.generate(15, (i) => _file('f$i.md'));
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded(many),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      // N / M still visible.
      expect(findPreviewTitle('1 / 15'), findsOneWidget);
      // No CircleAvatar dots are rendered inside the preview.
      expect(
        find.descendant(
          of: find.byType(WorkdirPreviewPage),
          matching: find.byType(CircleAvatar),
        ),
        findsNothing,
      );
    });

    testWidgets('non-previewable slot renders Can\'t preview without fetching',
        (tester) async {
      var fetchCalls = 0;
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.png'), _file('paper.pdf')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async {
          fetchCalls++;
          return _tinyPng;
        },
      )));
      await tester.pump();

      // Open at the image (slot 0); only that slot should fetch.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(fetchCalls, 1);

      // Move to the PDF slot. PDFs are non-previewable, so the pager
      // must NOT call fetchBytes — it short-circuits to _CannotPreview.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(fetchCalls, 1);
      expect(find.text("Can't preview this file"), findsOneWidget);
    });

    testWidgets('Retry twice on the same slide invalidates each cached future',
        (tester) async {
      // The cache + retry-token pair must allow consecutive retries on
      // the same slide: each Retry tap clears the cache for that file
      // and re-runs fetch. A regression that reused the failed future
      // would leave fetchCalls at 1 across all retries.
      var attempts = 0;
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async {
          attempts++;
          if (attempts < 3) throw Exception('boom-$attempts');
          return _tinyPng;
        },
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text("Couldn't load preview"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text("Couldn't load preview"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 3);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('bytes cache prevents refetch on swipe back', (tester) async {
      final fetchCounts = <String, int>{};
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (file) async {
          fetchCounts[file.filename] = (fetchCounts[file.filename] ?? 0) + 1;
          return Uint8List.fromList(utf8.encode('hi'));
        },
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(fetchCounts['a.md'], 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fetchCounts['b.md'], 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Returning to a.md must reuse the cached Future, not refetch.
      expect(fetchCounts['a.md'], 1);
    });

    testWidgets('arrowLeft at first slide is a no-op (no wrap, no exception)',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();
      expect(findPreviewTitle('1 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Still on the first slide; a regression to modular wrap would
      // jump to '2 / 2'.
      expect(findPreviewTitle('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('arrowRight at last slide is a no-op (no wrap, no exception)',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md'), _file('b.md')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(findPreviewTitle('2 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(findPreviewTitle('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('decode-failure fallbacks distinguish the cause', () {
    // Each failure mode should render a distinct message so a corrupt
    // file isn't conflated with an unsupported one.

    testWidgets('empty bytes show the "File is empty" message', (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('File is empty'), findsOneWidget);
      // Distinct from the generic unsupported-kind message — a
      // regression that collapsed both into "Can't preview this file"
      // would hide a real backend defect (empty artifact) behind the
      // generic-fallback copy.
      expect(find.text("Can't preview this file"), findsNothing);
    });

    testWidgets(
        'text-shaped file with invalid UTF-8 routes to the binary fallback',
        (tester) async {
      // 0xFF/0xFE are never valid UTF-8 lead bytes. A regression that
      // dropped the strict-decode try would silently render U+FFFD
      // mojibake — the test would then see the decoded content rather
      // than the dedicated "binary" message.
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('config.txt')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async =>
            Uint8List.fromList(const [0xFF, 0xFE, 0xFD, 0xFC]),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('This file looks binary'), findsOneWidget);
      // Download remains available so the user can still grab the
      // bytes from the fallback body.
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('invalid image bytes show the "image looks corrupt" message',
        (tester) async {
      // `.png` filename routes to the image branch; Image.memory's
      // errorBuilder fires for non-PNG bytes and the page swaps to
      // _ImageOrFallback's fallback. A regression that collapsed image
      // and generic fallbacks would lose this specific copy.
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async =>
            Uint8List.fromList(const [0x00, 0x01, 0x02, 0x03]),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('This image looks corrupt'), findsOneWidget);
      expect(find.text("Can't preview this file"), findsNothing);
      expect(find.text('This file looks binary'), findsNothing);
    });

    testWidgets('invalid svg content shows the "SVG looks corrupt" message',
        (tester) async {
      // `.svg` routes through the text-decode path, then SvgPreview's
      // parser rejects the content and swaps in its fallback. Distinct
      // from the image corrupt-copy and the generic unsupported copy.
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('chart.svg')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async =>
            Uint8List.fromList('not actually svg'.codeUnits),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('This SVG looks corrupt'), findsOneWidget);
      expect(find.text('This image looks corrupt'), findsNothing);
      expect(find.text("Can't preview this file"), findsNothing);
    });
  });

  group("the preview's title-bar download", () {
    Future<void> openPreview(
      WidgetTester tester,
      List<String> names, {
      required Future<DownloadOutcome> Function(WorkdirFile file) onDownload,
      int index = 0,
    }) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          capturedContext = context;
          return const Scaffold(body: SizedBox.shrink());
        }),
      ));
      WorkdirPreviewPage.show(
        context: capturedContext,
        files: [for (final n in names) _file(n)],
        initialIndex: index,
        fetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
        downloads: testDownloads(onDownload),
      );
      await tester.pumpAndSettle();
    }

    // The download's spinner never settles, so a page turn is pumped
    // through rather than settled: 300 ms outlasts the pager's 200 ms
    // animation.
    Future<void> pageTurn(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    final titleBarDownload = find.byTooltip('Download');
    final centredDownload = find.widgetWithText(SoliplexButton, 'Download');

    testWidgets('saves the shown file from a page that shows it',
        (tester) async {
      final saved = <String>[];
      await openPreview(tester, ['a.md', 'b.md'], index: 1, onDownload: (f) {
        saved.add(f.filename);
        return Future.value(DownloadOutcome.success);
      });

      await tester.tap(titleBarDownload);
      await tester.pump();

      expect(saved, ['b.md']);
      expect(find.byTooltip('Saved'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(titleBarDownload, findsOneWidget);
    });

    testWidgets('Close stays put while the download runs', (tester) async {
      final pending = Completer<DownloadOutcome>();
      await openPreview(tester, ['a.md'], onDownload: (_) => pending.future);
      final idle = tester.getRect(find.byTooltip('Close'));

      await tester.tap(titleBarDownload);
      await tester.pump();

      expect(find.byTooltip('Downloading'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('Close')), idle);
      pending.complete(DownloadOutcome.success);
      await tester.pump(const Duration(seconds: 2));
    },
        // Material sizes buttons smaller on desktop.
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.macOS}));

    testWidgets("shows the failure on the file's page", (tester) async {
      await openPreview(tester, ['a.md'],
          onDownload: (_) async => DownloadOutcome.failed);

      await tester.tap(titleBarDownload);
      await tester.pump();

      expect(find.byTooltip('Download failed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets("shares its download with the page's own Download button",
        (tester) async {
      final pending = Completer<DownloadOutcome>();
      var downloads = 0;
      await openPreview(tester, ['report.pdf'], onDownload: (_) {
        downloads++;
        return pending.future;
      });

      await tester.tap(titleBarDownload);
      await tester.pump();

      final button = tester.widget<SoliplexButton>(centredDownload);
      expect(button.isLoading, isTrue);
      await tester.tap(centredDownload, warnIfMissed: false);
      await tester.pump();
      expect(downloads, 1);

      pending.complete(DownloadOutcome.success);
      await tester.pump();
      expect(find.byTooltip('Saved'), findsOneWidget);
      expect(find.widgetWithText(SoliplexButton, 'Saved'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
        "paging shows the next file's download, and back shows this "
        "file's again", (tester) async {
      final pending = Completer<DownloadOutcome>();
      final saved = <String>[];
      await openPreview(tester, ['a.md', 'b.md'], onDownload: (f) {
        saved.add(f.filename);
        return f.filename == 'a.md'
            ? pending.future
            : Future.value(DownloadOutcome.success);
      });

      await tester.tap(titleBarDownload);
      await tester.pump();
      expect(titleBarDownload, findsNothing, reason: 'a.md is downloading');

      await tester.tap(find.byTooltip('Next'));
      await pageTurn(tester);
      expect(titleBarDownload, findsOneWidget, reason: 'b.md is idle');

      await tester.tap(find.byTooltip('Previous'));
      await pageTurn(tester);
      expect(titleBarDownload, findsNothing,
          reason: "a.md's download is still under way");

      await tester.tap(find.byTooltip('Next'));
      await pageTurn(tester);
      await tester.tap(titleBarDownload);
      await tester.pump();
      expect(saved, ['a.md', 'b.md']);

      pending.complete(DownloadOutcome.success);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a download outlives the preview it started in',
        (tester) async {
      final pending = Completer<DownloadOutcome>();
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('a.md')]),
        onRetry: () {},
        onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
        onDownload: (_) => pending.future,
      )));
      await tester.pump();
      await tester.tap(findFileName('a.md'));
      await tester.pumpAndSettle();

      await tester.tap(_inPreview(titleBarDownload));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 500));
      pending.complete(DownloadOutcome.success);
      await tester.pump();

      expect(find.byType(WorkdirPreviewPage), findsNothing);
      expect(find.byTooltip('Saved'), findsOneWidget, reason: 'on its row');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('keeps the failure colour while it cannot be pressed',
        (tester) async {
      await openPreview(tester, ['a.md'],
          onDownload: (_) async => DownloadOutcome.failed);

      await tester.tap(titleBarDownload);
      await tester.pump();

      final error = Theme.of(tester.element(find.byType(WorkdirPreviewPage)))
          .colorScheme
          .error;
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      final painted = tester
          .widget<RichText>(
            find.descendant(
              of: find.byIcon(Icons.error_outline),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      expect(icon.color, error);
      expect(painted, error);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a screen reader hears the download under way once',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final pending = Completer<DownloadOutcome>();
      try {
        await openPreview(tester, ['a.md'], onDownload: (_) => pending.future);

        await tester.tap(titleBarDownload);
        await tester.pump();

        expect(
          find.semantics.byPredicate((node) {
            final data = node.getSemanticsData();
            return data.label.contains('Downloading') ||
                data.tooltip.contains('Downloading');
          }),
          findsOne,
        );
      } finally {
        semantics.dispose();
      }
      pending.complete(DownloadOutcome.success);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group("the preview's Download button (via empty-bytes path)", () {
    // Empty bytes on an otherwise-previewable file route to
    // _CannotPreview, giving us a clean way to drive the shared
    // download-feedback state machine end-to-end through the preview
    // page.

    testWidgets('a download under way loads the button at its size',
        (tester) async {
      // A loading button keeps its label, hidden, so it keeps its size: the
      // spinner says what is happening, and the label still names it.
      final completer = Completer<DownloadOutcome>();
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) => completer.future,
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      final button = find.byType(SoliplexButton);
      final idle = tester.getSize(button);

      await tester.tap(find.text('Download'));
      await tester.pump();

      expect(tester.widget<SoliplexButton>(button).isLoading, isTrue);
      expect(tester.getSize(button), idle);

      completer.complete(DownloadOutcome.success);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('successful download flips Download → Saved, reverts after 2s',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.success,
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pump();

      expect(find.text('Saved'), findsOneWidget);
      expect(_inButton(find.byIcon(Icons.check)), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('a failed download says Download failed', (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.failed,
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pump();

      expect(find.text('Download failed'), findsOneWidget);
      expect(_inButton(find.byIcon(Icons.error_outline)), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('cancelled stays idle — no feedback swap', (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => DownloadOutcome.cancelled,
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pump();

      // Inside the preview, still on the idle Download label.
      expect(
        find.descendant(
          of: find.byType(WorkdirPreviewPage),
          matching: find.text('Download'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(WorkdirPreviewPage),
          matching: find.text('Saved'),
        ),
        findsNothing,
      );
    });

    testWidgets('throwing onDownload still flips to the error state',
        (tester) async {
      await tester.pumpWidget(_wrap(_workspace(
        status: WorkdirFilesLoaded([_file('plot.png')]),
        onRetry: () {},
        onDownload: (_) async => throw Exception('boom'),
        onFetchBytes: (_) async => Uint8List(0),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pump();

      expect(_inButton(find.byIcon(Icons.error_outline)), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('sub-tablet width opens the preview as a Scaffold, not a Dialog',
      (tester) async {
    // Phone-width opens through Navigator.push, not showGeneralDialog, so
    // no Dialog widget should be present. A regression flipping the
    // breakpoint comparison would still pass every dialog-shaped test
    // because the dialog path is hit on the test view's default size.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('plot.png')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(WorkdirPreviewPage), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('arrow-key release does not advance the pager a second time',
      (tester) async {
    // The pager handles KeyDownEvent/KeyRepeatEvent and ignores KeyUpEvent.
    // A regression that routes through KeyUpEvent (e.g. swapped branches in
    // _handleKey) would double-advance on a single physical keypress because
    // sendKeyEvent fires Down followed by Up. Send Down then Up separately
    // and pin that only the Down advances.
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('a.md'), _file('b.md'), _file('c.md')]),
      onRetry: () {},
      onDownload: (_) async => DownloadOutcome.success,
      onFetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(findPreviewTitle('2 / 3'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(findPreviewTitle('2 / 3'), findsOneWidget);
  });

  testWidgets(
      'WorkdirPreviewPage.show clamps an out-of-range initialIndex to the last file',
      (tester) async {
    // show() must not assert/crash on a caller-supplied out-of-range
    // index; it clamps to a valid slide.
    final files = [_file('a.png'), _file('b.png'), _file('c.png')];
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        capturedContext = context;
        return const Scaffold(body: SizedBox.shrink());
      }),
    ));

    WorkdirPreviewPage.show(
      context: capturedContext,
      files: files,
      initialIndex: 99,
      fetchBytes: (_) async => _tinyPng,
      downloads: testDownloads(),
    );
    await tester.pumpAndSettle();

    expect(findPreviewTitle('3 / 3'), findsOneWidget);
    expect(findPreviewTitle('c.png'), findsOneWidget);
  });

  group('nested paths', () {
    const path = 'crm_app/backend/models/customer.py';
    // A flat list shows each file's directory; Folders shows it as rows.
    const directory = 'crm_app/backend/models/';

    Future<void> pumpRow(
      WidgetTester tester, {
      required double width,
      String name = path,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: _workspace(
                  status: WorkdirFilesLoaded([_file(name)]),
                  onRetry: () {},
                  onDownload: (_) async => DownloadOutcome.success,
                  onFetchBytes: (_) async => Uint8List(0),
                  sort: FileSort.nameAToZ,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    bool isCut(WidgetTester tester, Finder text) =>
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

    testWidgets(
        'a row shows the basename, then the directory muted with a slash',
        (tester) async {
      await pumpRow(tester, width: 800);

      expect(find.text(path), findsNothing);
      expect(findFileName('customer.py'), findsOneWidget);
      expect(find.text(directory), findsOneWidget);
      Color? painted(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .text
          .style
          ?.color;
      expect(painted(directory), isNot(painted('stomer.py')));
    });

    testWidgets('a narrow row cuts the directory, never the basename',
        (tester) async {
      await pumpRow(tester, width: 320);

      expect(isCut(tester, find.text('cu')), isFalse);
      expect(isCut(tester, find.text('stomer.py')), isFalse);
      expect(isCut(tester, find.text(directory)), isTrue);
    });

    testWidgets(
        'a row too narrow for the basename hides the directory '
        'and keeps its end', (tester) async {
      // Room for `stomer.py`, not for `customer.py`.
      await pumpRow(tester, width: 216);

      expect(isCut(tester, find.text('cu')), isTrue);
      expect(isCut(tester, find.text('stomer.py')), isFalse);
      expect(tester.getSize(find.text(directory)).width, 0);
    });

    testWidgets('a cut name stops short of the preview button', (tester) async {
      // A cut name ends at the action's padding, never at the icon itself.
      await pumpRow(tester, width: 180);

      final end = tester.getRect(find.text('stomer.py'));
      final eye = tester.getRect(find.byIcon(Icons.visibility_outlined));
      expect(
        eye.left - end.right,
        greaterThanOrEqualTo(SoliplexSpacing.s1),
      );
    });

    testWidgets('a row at a large text size stays within its slot',
        (tester) async {
      const name = 'quarterly_report_final.xlsx';
      await pumpRow(tester, width: 420, name: name);
      expect(isCut(tester, find.text('quarterly_report')), isFalse,
          reason: 'the name fits at 1x');

      await pumpRow(tester, width: 420, name: name, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(isCut(tester, find.text('quarterly_report')), isTrue);
      expect(isCut(tester, find.text('_final.xlsx')), isFalse);
    });

    testWidgets('a cut name leaves no gap before the end it keeps',
        (tester) async {
      // A slot that is no whole number of the test font's glyphs, so the cut
      // head's text ends short of it.
      await pumpRow(tester,
          width: 306, name: 'exports/output_20261105_1432.csv');

      final head =
          tester.renderObject<RenderParagraph>(find.text('output_2026110'));
      final painted = head
          .getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: head.text.toPlainText().length,
            ),
          )
          .fold(0.0, (right, box) => math.max(right, box.right));
      expect(head.size.width, moreOrLessEquals(painted, epsilon: 1));
    });

    testWidgets(
        'names that differ only before the extension stay apart when cut',
        (tester) async {
      // Room for the end `5_1432.csv`, not for the whole name.
      await pumpRow(tester,
          width: 300, name: 'exports/output_20261105_1432.csv');

      expect(isCut(tester, find.text('output_2026110')), isTrue);
      expect(isCut(tester, find.text('5_1432.csv')), isFalse);
    });

    testWidgets('the row tooltip names the full path', (tester) async {
      await pumpRow(tester, width: 800);

      expect(find.byTooltip(path), findsOneWidget);
    });

    testWidgets('a screen reader hears the full path once', (tester) async {
      // Narrow enough that the visible basename is cut: what is announced
      // must not follow the cut.
      await pumpRow(tester, width: 180);

      final data =
          tester.getSemantics(find.byType(WorkdirFileRow)).getSemanticsData();
      expect(data.label, path);
      expect(data.tooltip, isEmpty, reason: 'the label already names it');
    });

    group('preview header', () {
      Future<void> openPreview(
        WidgetTester tester,
        List<String> names, {
        int index = 0,
      }) async {
        final files = [for (final n in names) _file(n)];
        late BuildContext capturedContext;
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            capturedContext = context;
            return const Scaffold(body: SizedBox.shrink());
          }),
        ));
        WorkdirPreviewPage.show(
          context: capturedContext,
          files: files,
          initialIndex: index,
          fetchBytes: (_) async => Uint8List.fromList(utf8.encode('body')),
          downloads: testDownloads(),
        );
        await tester.pumpAndSettle();
      }

      void usePhoneWidth(WidgetTester tester) {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }

      testWidgets('titles a nested file by its basename', (tester) async {
        await openPreview(tester, ['reports/a.md', 'reports/b.md'], index: 1);

        expect(_inPreview(findPreviewTitle('b.md')), findsOneWidget);
      });

      testWidgets('puts the directory after the position', (tester) async {
        await openPreview(tester, ['reports/a.md', 'notes.md']);

        expect(findPreviewTitle('1 / 2 · reports/'), findsOneWidget);
      });

      testWidgets('shows the directory alone for a single nested file',
          (tester) async {
        await openPreview(tester, ['reports/a.md']);

        expect(_inPreview(findPreviewTitle('reports/')), findsOneWidget);
      });

      testWidgets('wraps a long name and directory whole on a phone',
          (tester) async {
        usePhoneWidth(tester);
        const directory = 'reports/regional/quarterly/2026/drafts';
        const name = 'quarterly_revenue_by_region_and_product_line_2026.md';

        await openPreview(tester, ['$directory/$name', 'notes.md']);

        int lines(Finder text) {
          final paragraph = tester.renderObject<RenderParagraph>(text);
          return (paragraph.size.height / paragraph.preferredLineHeight)
              .round();
        }

        final title = _inPreview(findPreviewTitle(name));
        final subtitle = _inPreview(findPreviewTitle('1 / 2 · $directory/'));
        expect(isCut(tester, title), isFalse);
        expect(isCut(tester, subtitle), isFalse);
        expect(lines(title), greaterThan(1));
        expect(lines(subtitle), greaterThan(1));
      });

      testWidgets('breaks a long name between its words', (tester) async {
        usePhoneWidth(tester);
        const name = 'quarterly_revenue_by_region_and_product_line_2026.md';

        await openPreview(tester, [name]);

        final paragraph = tester.renderObject<RenderParagraph>(
          _inPreview(findPreviewTitle(name)),
        );
        final firstLineEnd = paragraph.getPositionForOffset(
          Offset(paragraph.size.width, paragraph.preferredLineHeight / 2),
        );
        final firstLine = paragraph.text
            .toPlainText()
            .substring(0, firstLineEnd.offset)
            .replaceAll('\u200B', '');
        expect(firstLine, endsWith('_'));
      });

      testWidgets('a screen reader hears the title as written', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await openPreview(tester, ['reports/q_1.md', 'notes.md']);

          expect(_inPreview(find.bySemanticsLabel('q_1.md')), findsOneWidget);
          expect(
            _inPreview(find.bySemanticsLabel('1 / 2 · reports/')),
            findsOneWidget,
          );
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('a short title sits level with the actions', (tester) async {
        await openPreview(tester, ['reports/a.md']);

        final title = tester.getRect(find.ancestor(
          of: _inPreview(findPreviewTitle('a.md')),
          matching: find.byType(SingleChildScrollView),
        ));
        final close = tester.getRect(find.byTooltip('Close'));
        expect(title.center.dy, moreOrLessEquals(close.center.dy, epsilon: 1));
      },
          // Material sizes buttons smaller on desktop.
          variant: TargetPlatformVariant(
              {TargetPlatform.android, TargetPlatform.macOS}));

      testWidgets('has actions 48 px square on every platform', (tester) async {
        await openPreview(tester, ['reports/a.md']);

        for (final icon in [Icons.download_outlined, Icons.close]) {
          expect(
            tester.getSize(find.widgetWithIcon(IconButton, icon)),
            const Size.square(kMinInteractiveDimension),
          );
        }
      },
          // Material sizes buttons smaller on desktop.
          variant: TargetPlatformVariant(
              {TargetPlatform.android, TargetPlatform.macOS}));

      testWidgets('has no tooltip, the full name being in sight',
          (tester) async {
        await openPreview(tester, ['reports/a.md']);

        expect(_inPreview(findPreviewTitle('a.md')), findsOneWidget);
        expect(
          find.ancestor(
            of: _inPreview(findPreviewTitle('a.md')),
            matching: find.byType(Tooltip),
          ),
          findsNothing,
        );
      });

      testWidgets(
          'a name too long for a third of the preview scrolls there, leaving '
          'the rest to the file', (tester) async {
        // A phone on its side: short, and narrower than the dialog's
        // breakpoint.
        tester.view.physicalSize = const Size(568, 320);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final name = '${'x' * 250}.md';

        await openPreview(tester, [name]);

        expect(tester.takeException(), isNull);
        expect(
          find.ancestor(
            of: _inPreview(findPreviewTitle(name)),
            matching: find.byType(Scrollable),
          ),
          findsOneWidget,
        );
        final title = tester.getRect(find.ancestor(
          of: _inPreview(findPreviewTitle(name)),
          matching: find.byType(SingleChildScrollView),
        ));
        expect(title.height, lessThanOrEqualTo(320 / 3));

        // The rest of the name is reachable by scrolling the title.
        final top = tester.getTopLeft(_inPreview(findPreviewTitle(name))).dy;
        await tester.dragFrom(title.center, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(_inPreview(findPreviewTitle(name))).dy,
          lessThan(top),
        );
        expect(
          tester.getSize(find.byType(PageView)).height,
          greaterThan(320 / 2),
        );
      });

      testWidgets('a name too long for a third of the dialog scrolls there',
          (tester) async {
        // Wide enough for the dialog, which is at most 85% of the height.
        tester.view.physicalSize = const Size(1000, 450);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final name = '${'x' * 2000}.md';

        await openPreview(tester, [name]);

        expect(find.byType(Dialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.ancestor(
          of: _inPreview(findPreviewTitle(name)),
          matching: find.byType(SingleChildScrollView),
        ));
        expect(title.height, lessThanOrEqualTo(450 * 0.85 / 3));
      });
    });
  });
}
