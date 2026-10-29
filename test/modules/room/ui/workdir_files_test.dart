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

import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

import '../../../helpers/file_name_finder.dart';

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

// The list underneath a preview still renders each row's FileName, so an
// unqualified findFileName('x.md') can hit two widgets. Scope finders to the
// preview page widget tree where it matters.
Finder _inPreview(Finder f) => find.descendant(
      of: find.byType(WorkdirPreviewPage),
      matching: f,
    );

/// A [WorkspaceFilesSection] whose folders keep their default state: these
/// tests are about the rows and the preview, not about opening folders.
WorkspaceFilesSection _workspace({
  required WorkdirFilesStatus status,
  required VoidCallback onRetry,
  required Future<DownloadOutcome> Function(WorkdirFile file) onDownload,
  required Future<Uint8List> Function(WorkdirFile file) onFetchBytes,
}) =>
    WorkspaceFilesSection(
      status: status,
      onRetry: onRetry,
      onDownload: onDownload,
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
  });

  testWidgets('second tap during an in-flight download is a no-op',
      (tester) async {
    final completer = Completer<DownloadOutcome>();
    var calls = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) {
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

  testWidgets(
      'download InkWell is wired with a null onTap while a download is in flight',
      (tester) async {
    // A bare _handleTap early-return would also drop a second tap, so
    // the no-op test above does not prove the disabled state. This
    // asserts build() actively wires onTap to null mid-flight, which
    // is what gives the user the disabled InkWell ripple / a11y state.
    final completer = Completer<DownloadOutcome>();
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) => completer.future,
    )));
    await tester.pump();

    final downloadIcon = find.byIcon(Icons.download_outlined);
    final inkWellBeforeTap = tester.widget<InkWell>(
      find.ancestor(of: downloadIcon, matching: find.byType(InkWell)).first,
    );
    expect(inkWellBeforeTap.onTap, isNotNull);

    await tester.tap(downloadIcon);
    await tester.pump();

    final inkWellDuringFlight = tester.widget<InkWell>(
      find.ancestor(of: downloadIcon, matching: find.byType(InkWell)).first,
    );
    expect(inkWellDuringFlight.onTap, isNull);

    completer.complete(DownloadOutcome.success);
    await tester.pumpAndSettle();
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

  testWidgets('second tap during feedback window is a no-op', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_wrap(_workspace(
      status: WorkdirFilesLoaded([_file('report.pdf')]),
      onRetry: () {},
      onFetchBytes: (_) async => _tinyPng,
      onDownload: (_) async {
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
      expect(_inPreview(findFileName('b.md')), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
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
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(WorkdirPreviewPage),
        matching: find.widgetWithIcon(IconButton, Icons.chevron_right),
      ));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);

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
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(_inPreview(findFileName('b.md')), findsOneWidget);
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
      expect(find.text('1 / 3'), findsOneWidget);

      // Tap the third dot — InkResponses inside the preview's dots row
      // each carry the filename tooltip. The third one is at index 2.
      await tester.tap(find.descendant(
        of: find.byType(WorkdirPreviewPage),
        matching: find.byTooltip('c.md'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3 / 3'), findsOneWidget);
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
      expect(find.text('1 / 15'), findsOneWidget);
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
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Still on the first slide; a regression to modular wrap would
      // jump to '2 / 2'.
      expect(find.text('1 / 2'), findsOneWidget);
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
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
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

  group('DownloadFeedbackButton (via empty-bytes path)', () {
    // Empty bytes on an otherwise-previewable file route to
    // _CannotPreview, giving us a clean way to drive the shared
    // download-feedback state machine end-to-end through the preview
    // page.

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
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('failed download flips to Couldn\'t save', (tester) async {
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

      expect(find.text("Couldn't save"), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
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
      onDownload: (_) async => DownloadOutcome.success,
    );
    await tester.pumpAndSettle();

    expect(find.text('3 / 3'), findsOneWidget);
    expect(findFileName('c.png'), findsOneWidget);
  });

  group('nested paths', () {
    const path = 'crm_app/backend/models/customer.py';

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
      expect(find.text('customer'), findsOneWidget);
      expect(find.text('.py'), findsOneWidget);
      expect(find.text('backend/models/'), findsOneWidget);
      Color? painted(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .text
          .style
          ?.color;
      expect(painted('backend/models/'), isNot(painted('customer')));
    });

    testWidgets('a narrow row cuts the directory, never the basename',
        (tester) async {
      await pumpRow(tester, width: 320);

      expect(isCut(tester, find.text('customer')), isFalse);
      expect(isCut(tester, find.text('backend/models/')), isTrue);
    });

    testWidgets(
        'a row too narrow for the basename hides the directory '
        'and keeps the extension', (tester) async {
      await pumpRow(tester, width: 180);

      expect(isCut(tester, find.text('customer')), isTrue);
      expect(isCut(tester, find.text('.py')), isFalse);
      expect(tester.getSize(find.text('backend/models/')).width, 0);
    });

    testWidgets('a cut name stops short of the preview button', (tester) async {
      // The eye has no padding of its own, unlike the download button.
      await pumpRow(tester, width: 180);

      final extension = tester.getRect(find.text('.py'));
      final eye = tester.getRect(find.byIcon(Icons.visibility_outlined));
      expect(
        eye.left - extension.right,
        greaterThanOrEqualTo(SoliplexSpacing.s1),
      );
    });

    testWidgets('a row at a large text size stays within its slot',
        (tester) async {
      const name = 'quarterly_report_final.xlsx';
      await pumpRow(tester, width: 420, name: name);
      expect(isCut(tester, find.text('quarterly_report_final')), isFalse,
          reason: 'the name fits at 1x');

      await pumpRow(tester, width: 420, name: name, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(isCut(tester, find.text('quarterly_report_final')), isTrue);
      expect(isCut(tester, find.text('.xlsx')), isFalse);
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
          onDownload: (_) async => DownloadOutcome.success,
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

        expect(_inPreview(findFileName('b.md')), findsOneWidget);
      });

      testWidgets('puts the directory after the position', (tester) async {
        await openPreview(tester, ['reports/a.md', 'notes.md']);

        expect(find.text('1 / 2 · reports/'), findsOneWidget);
      });

      testWidgets('shows the directory alone for a single nested file',
          (tester) async {
        await openPreview(tester, ['reports/a.md']);

        expect(_inPreview(find.text('reports/')), findsOneWidget);
      });

      testWidgets("the title's tooltip names the shown file's full path",
          (tester) async {
        await openPreview(tester, ['reports/a.md', 'reports/b.md'], index: 1);

        // The page dots carry tooltips too; this is the one over the name.
        final title = find.ancestor(
          of: _inPreview(find.byType(FileName)),
          matching: find.byType(Tooltip),
        );
        expect(tester.widget<Tooltip>(title).message, 'reports/b.md');
      });

      testWidgets("the title's tooltip covers only the name and directory",
          (tester) async {
        await openPreview(tester, ['reports/a.md']);

        // A tooltip shows at its target's centre: a target as wide as the
        // bar would show it far from a short name.
        final title = find.ancestor(
          of: _inPreview(find.byType(FileName)),
          matching: find.byType(Tooltip),
        );
        final name = tester.getRect(_inPreview(find.byType(FileName)));
        final directory = tester.getRect(_inPreview(find.text('reports/')));
        expect(
          tester.getRect(title).right,
          math.max(name.right, directory.right),
        );
      });

      testWidgets("a screen reader hears the title's name once",
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await openPreview(tester, ['reports/a.md']);

          final data = tester
              .getSemantics(_inPreview(find.byType(FileName)))
              .getSemanticsData();
          expect(
            data.tooltip,
            isEmpty,
            reason: 'the name and the line below it already read the path',
          );
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('keeps the extension of a long basename', (tester) async {
        usePhoneWidth(tester);

        await openPreview(tester, ['quarterly_revenue_by_region_2026.md']);

        expect(isCut(tester, _inPreview(find.text('.md'))), isFalse);
        expect(
          isCut(tester,
              _inPreview(find.text('quarterly_revenue_by_region_2026'))),
          isTrue,
        );
      });

      testWidgets('announces the whole basename while its text is cut',
          (tester) async {
        // The cut is what a screen reader must not follow.
        usePhoneWidth(tester);
        await openPreview(tester, ['quarterly_revenue_by_region_2026.md']);

        expect(
          _inPreview(
              find.bySemanticsLabel('quarterly_revenue_by_region_2026.md')),
          findsOneWidget,
        );
      });
    });
  });
}
