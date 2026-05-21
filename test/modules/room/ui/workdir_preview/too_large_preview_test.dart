import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/download_outcome.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/too_large_preview.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the too-large message and a Download button',
      (tester) async {
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () async => DownloadOutcome.success,
    )));

    expect(find.text('File is too large to preview'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('success download swaps to Saved + check, reverts after 2s',
      (tester) async {
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () async => DownloadOutcome.success,
    )));

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('failed download shows Couldn\'t save + error icon',
      (tester) async {
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () async => DownloadOutcome.failed,
    )));

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.text("Couldn't save"), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('cancelled stays idle — no feedback swap', (tester) async {
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () async => DownloadOutcome.cancelled,
    )));

    await tester.tap(find.text('Download'));
    await tester.pump();

    // Still on the idle Download button.
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text("Couldn't save"), findsNothing);
  });

  testWidgets('throwing onDownload still flips to the error state',
      (tester) async {
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () async => throw Exception('boom'),
    )));

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('byte-size formatting pins the KB and MB thresholds',
      (tester) async {
    // _formatBytes uses >= for both KB and MB. A regression to > on
    // either boundary would round the boundary case to the smaller
    // unit (e.g. "1024 B" instead of "1 KB").
    Future<void> pumpFor(int bytes) => tester.pumpWidget(_wrap(TooLargePreview(
          filename: 'huge.log',
          byteSize: bytes,
          capBytes: 5 * 1024 * 1024,
          onDownload: () async => DownloadOutcome.success,
        )));

    await pumpFor(1024);
    expect(find.textContaining('1 KB'), findsOneWidget,
        reason: '1024 bytes must round up to the KB unit, not stay as B');

    await pumpFor(1024 * 1024);
    expect(find.textContaining('1.0 MB'), findsOneWidget,
        reason: '1 MiB must round up to the MB unit, not stay as KB');
  });

  testWidgets('second tap during an in-flight download is a no-op',
      (tester) async {
    final completer = Completer<DownloadOutcome>();
    var calls = 0;
    await tester.pumpWidget(_wrap(TooLargePreview(
      filename: 'huge.log',
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      onDownload: () {
        calls++;
        return completer.future;
      },
    )));

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(calls, 1);

    // The button is disabled while in-flight; tap is still attempted
    // but the handler short-circuits via _inFlight.
    await tester.tap(find.text('Download'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    completer.complete(DownloadOutcome.success);
    await tester.pumpAndSettle();
  });
}
