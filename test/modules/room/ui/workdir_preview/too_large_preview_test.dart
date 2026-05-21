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
