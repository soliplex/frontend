import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart';

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

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // Image previews share Flutter's global imageCache; a partially-decoded
  // entry from one test will resurface as a "Codec failed" error in the
  // next, masking real failures.
  setUp(() => PaintingBinding.instance.imageCache.clear());

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

  testWidgets(
      'preview eye icon shown only for image files when onPreview is wired',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png'), _file('report.pdf')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('preview eye icon hidden when onPreview is null even for images',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
  });

  testWidgets('tapping the eye opens the preview page and fetches bytes',
      (tester) async {
    var fetchCalls = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-7',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (runId, file) async {
        fetchCalls++;
        expect(runId, 'run-7');
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

    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('preview shows generic error + Retry when fetch fails',
      (tester) async {
    var fetchCalls = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async {
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
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => throw const NotFoundException(
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
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('PLOT.PNG')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets(
      'empty bytes short-circuit to Download (not Retry), no InteractiveViewer',
      (tester) async {
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => Uint8List(0),
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
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => _htmlBytes,
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
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png'), _file('report.pdf')],
      onDownload: (_, __) async => DownloadOutcome.success,
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets(
      'previewable file uses insert_drive_file icon when onPreview is null',
      (tester) async {
    // image_outlined is reserved for rows that can actually preview. Without
    // onPreview wired, an image file row is no different from any other file.
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async => DownloadOutcome.success,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets(
      'tapping a previewable row opens the preview and does not download',
      (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    // Tap the filename text — that's a non-icon part of the row body, so it
    // exercises the row InkWell rather than either trailing icon.
    await tester.tap(find.text('plot.png'));
    await tester.pumpAndSettle();

    expect(downloads, 0);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
      'tapping the trailing download icon on a previewable row downloads',
      (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(WorkdirFilesSection(
      runId: 'run-1',
      fetchFiles: (_) async => [_file('plot.png')],
      onDownload: (_, __) async {
        downloads++;
        return DownloadOutcome.success;
      },
      onPreview: (_, __) async => _tinyPng,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(downloads, 1);
    // The preview dialog/page should not have opened.
    expect(find.byIcon(Icons.close), findsNothing);
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
