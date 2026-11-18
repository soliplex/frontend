import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_body.dart';
import 'package:soliplex_frontend/src/shared/zoomable_view.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

const _validSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
    'height="10"><circle cx="5" cy="5" r="4"/></svg>';

const _notice = "Couldn't render this SVG.";

Widget _inline(SvgBody body) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );

Widget _fill(SvgBody body) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 400, child: body)),
    );

void main() {
  testWidgets('fill layout gives the zoomable picture finite height',
      (tester) async {
    await tester.pumpWidget(_fill(const SvgBody(
      content: _validSvg,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(ZoomableView), findsOneWidget);
  });

  testWidgets('inline valid SVG opens a zoomable dialog on tap',
      (tester) async {
    await tester.pumpWidget(_inline(const SvgBody(
      content: _validSvg,
      fill: false,
      isStreaming: false,
      selectable: false,
    )));
    await tester.pump();

    // The inline picture is not itself the full-size viewer.
    expect(find.byType(ZoomableView), findsNothing);

    // The picture is laid out at zero size until the SVG rasterizes, so a
    // hit-test tap misses; invoke the wrapper's onTap directly.
    final gesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.byType(SvgPicture),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    gesture.onTap!();
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(ZoomableView),
      ),
      findsOneWidget,
    );
    // The dialog's close button sits where a header's copy button would.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byTooltip('Copy SVG'),
      ),
      findsNothing,
    );
  });

  testWidgets('fill layout shows the header', (tester) async {
    await tester.pumpWidget(_fill(const SvgBody(
      content: _validSvg,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text('svg'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.byTooltip('Copy SVG'), findsOneWidget);
  });

  testWidgets('switch shows the source', (tester) async {
    await tester.pumpWidget(_inline(const SvgBody(
      content: _validSvg,
      fill: false,
      isStreaming: false,
      selectable: false,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.textContaining('<circle', findRichText: true), findsOneWidget);
  });

  testWidgets(
      'inline malformed SVG shows the icon and notice text, and tap opens '
      'nothing', (tester) async {
    await tester.pumpWidget(_inline(const SvgBody(
      content: 'not valid <svg inline garbage',
      fill: false,
      isStreaming: false,
      selectable: false,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);

    await tester.tap(find.byIcon(Icons.broken_image));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('fill malformed SVG shows the notice and the source',
      (tester) async {
    const content = 'not valid <svg fill garbage';
    await tester.pumpWidget(_fill(const SvgBody(
      content: content,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsOneWidget);
    expect(find.textContaining('fill garbage', findRichText: true),
        findsOneWidget);
    expect(find.byType(ZoomableView), findsNothing);
  });

  testWidgets(
      'malformed SVG while streaming shows neither icon nor notice and logs '
      'nothing', (tester) async {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    const content = 'not valid <svg streaming garbage';
    Iterable<LogRecord> warnings() =>
        sink.records.where((r) => r.level == LogLevel.warning);

    await tester.pumpWidget(_inline(const SvgBody(
      content: content,
      fill: false,
      isStreaming: true,
      selectable: false,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(find.text(_notice), findsNothing);
    expect(warnings(), isEmpty);

    await tester.pumpWidget(_inline(const SvgBody(
      content: content,
      fill: false,
      isStreaming: false,
      selectable: false,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);
    final record = warnings().single;
    expect(record.error, isNull);
    expect(record.attributes['contentLength'], content.length);
    expect(record.attributes['failure'], isA<String>());
    expect(record.attributes.values.whereType<String>(),
        everyElement(isNot(contains('garbage'))));
  });

  testWidgets('a valid SVG replaced by a malformed one shows the notice',
      (tester) async {
    // The pager reuses the element across pages; a picture that kept the
    // previous content's rendering would never report the new failure.
    await tester.pumpWidget(_fill(const SvgBody(
      content: _validSvg,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_fill(const SvgBody(
      content: 'not valid <svg after-valid garbage',
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets('failure state resets when content changes', (tester) async {
    // Paging to a different file reuses the same SvgBody element with new
    // content; a failure that did not reset would stay stuck on a valid SVG.
    await tester.pumpWidget(_fill(const SvgBody(
      content: 'not valid <svg reset garbage',
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsOneWidget);

    await tester.pumpWidget(_fill(const SvgBody(
      content: _validSvg,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('malformed SVG that is not streaming logs one warning',
      (tester) async {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    const content = 'not valid <svg logged once garbage';

    await tester.pumpWidget(_fill(const SvgBody(
      content: content,
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    final record =
        sink.records.where((r) => r.level == LogLevel.warning).single;
    expect(record.error, isNull);
    expect(record.attributes['contentLength'], content.length);
  });

  testWidgets('inline picture is capped at 400 px tall', (tester) async {
    const tall = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
        'height="2000"><rect width="100" height="2000"/></svg>';
    await tester.runAsync(() async {
      await tester.pumpWidget(_inline(const SvgBody(
        content: tall,
        fill: false,
        isStreaming: false,
        selectable: false,
      )));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pump();

    expect(
        tester.getSize(find.byType(SvgPicture)).height, lessThanOrEqualTo(400));
    expect(tester.getSize(find.byType(SvgPicture)).height, greaterThan(0));
  });
}
