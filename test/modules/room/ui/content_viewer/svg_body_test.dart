import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/browser_svg_picture.dart';
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
    final semantics = tester.ensureSemantics();
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
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.bySemanticsLabel('SVG image'),
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
    semantics.dispose();
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

  testWidgets('fill malformed SVG offers no Preview / Source switch',
      (tester) async {
    await tester.pumpWidget(_fill(const SvgBody(
      content: 'not valid <svg fill switch garbage',
      fill: true,
      isStreaming: false,
      selectable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Source'), findsNothing);
    expect(find.byTooltip('Copy SVG'), findsOneWidget);
  });

  testWidgets('inline malformed SVG keeps the switch to its source',
      (tester) async {
    await tester.pumpWidget(_inline(const SvgBody(
      content: 'not valid <svg inline switch garbage',
      fill: false,
      isStreaming: false,
      selectable: false,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
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
    // The same body can be handed new content: a streamed fence, or a pager
    // page whose index shows another file after the listing refreshes. A
    // picture that kept the previous rendering would never report the new
    // failure.
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
    // A listing refresh can show another file in the same pager page, handing
    // the same body new content; a failure that did not reset would stay stuck
    // on a valid SVG.
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

  group('an SVG styled by a <style> sheet', () {
    const styled = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
        'height="100"><style>.box { fill: #00ff00; }</style>'
        '<rect class="box" width="100" height="100"/></svg>';

    testWidgets("paints its rules' colours", (tester) async {
      final key = GlobalKey();
      await _pumpLoaded(
        tester,
        RepaintBoundary(
          key: key,
          child: _fill(const SvgBody(
            content: styled,
            fill: true,
            isStreaming: false,
            selectable: false,
          )),
        ),
      );

      expect(await _centrePixel(tester, key), const Color(0xFF00FF00));
    });

    testWidgets('paints the rules of new content', (tester) async {
      const blue = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
          'height="100"><style>.box { fill: #0000ff; }</style>'
          '<rect class="box" width="100" height="100"/></svg>';
      final key = GlobalKey();
      Widget body(String content) => RepaintBoundary(
            key: key,
            child: _fill(SvgBody(
              content: content,
              fill: true,
              isStreaming: false,
              selectable: false,
            )),
          );

      await _pumpLoaded(tester, body(styled));
      await _pumpLoaded(tester, body(blue));

      expect(await _centrePixel(tester, key), const Color(0xFF0000FF));
    });

    testWidgets('paints its rules while streaming once the SVG is whole',
        (tester) async {
      // So the picture is not swapped, and reloaded, when streaming ends.
      final key = GlobalKey();
      await _pumpLoaded(
        tester,
        RepaintBoundary(
          key: key,
          child: _fill(const SvgBody(
            content: styled,
            fill: true,
            isStreaming: true,
            selectable: false,
          )),
        ),
      );

      expect(await _centrePixel(tester, key), const Color(0xFF00FF00));
    });

    testWidgets(
        'a sheet that cannot be read draws as written and logs one warning',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      const content = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><style>.unread { fill: #; }</style>'
          '<rect class="unread" width="10" height="10"/></svg>';

      await _pumpLoaded(
        tester,
        _fill(const SvgBody(
          content: content,
          fill: true,
          isStreaming: false,
          selectable: false,
        )),
      );

      final record =
          sink.records.where((r) => r.level == LogLevel.warning).single;
      expect(record.message, 'svg styles could not be inlined');
      expect(record.error, isNotNull);
      expect(record.attributes['contentLength'], content.length);
    });

    testWidgets('an SVG that fails inlined and as written shows the notice',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      // The transform attribute throws in flutter_svg in either form; the
      // sheet only makes the inlined SVG differ from the one as written.
      const content = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><style>.x { fill: red; }</style>'
          '<rect class="x" transform="bogus(1)" width="10" height="10"/>'
          '</svg>';

      await tester.pumpWidget(_fill(const SvgBody(
        content: content,
        fill: true,
        isStreaming: false,
        selectable: false,
      )));
      await tester.pumpAndSettle();

      expect(find.text(_notice), findsOneWidget);
      expect(
        sink.records
            .where((r) => r.level == LogLevel.warning)
            .map((r) => r.message),
        [
          'svg failed to render with its styles inlined; drawing it as written',
          'svg content failed to render',
        ],
      );
      // flutter_svg's errors quote the SVG, so only a description is logged.
      final inlined =
          sink.records.firstWhere((r) => r.level == LogLevel.warning);
      expect(inlined.error, isNull);
      expect(inlined.attributes['failure'], isA<String>());
    });

    testWidgets(
        'a picture that fails while streaming is drawn inlined once '
        'streaming ends', (tester) async {
      // A comment after the </svg> keeps it from counting as whole while
      // streaming, so it is drawn as written until streaming ends.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      // flutter_svg throws on a CSS transform as written; inlined, it is the
      // attribute's syntax.
      const content = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><style>.unused { fill: red; }</style>'
          '<rect style="transform: rotate(45deg)" width="10" height="10"/>'
          '</svg><!-- end -->';
      Widget body({required bool isStreaming}) => _fill(SvgBody(
            content: content,
            fill: true,
            isStreaming: isStreaming,
            selectable: false,
          ));

      await tester.pumpWidget(body(isStreaming: true));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNothing);
      await _pumpLoaded(tester, body(isStreaming: false));

      expect(find.text(_notice), findsNothing);
      expect(sink.records.where((r) => r.level == LogLevel.warning), isEmpty);
    });

    testWidgets(
        'a whole SVG that failed while streaming is not drawn again once '
        'streaming ends', (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      // The transform attribute throws in flutter_svg in either form. The SVG
      // differs from every other test's, so its failure is not logged yet.
      const content = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><style>.x { fill: blue; }</style>'
          '<rect class="x" transform="bogus(2)" width="10" height="10"/>'
          '</svg>';
      Widget body({required bool isStreaming}) => _fill(SvgBody(
            content: content,
            fill: true,
            isStreaming: isStreaming,
            selectable: false,
          ));

      await tester.pumpWidget(body(isStreaming: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(body(isStreaming: false));

      expect(find.byType(SvgPicture), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text(_notice), findsOneWidget);
      expect(
        sink.records
            .where((r) => r.level == LogLevel.warning)
            .map((r) => r.message),
        [
          'svg failed to render with its styles inlined; drawing it as written',
          'svg content failed to render',
        ],
      );
    });

    testWidgets('keeps its authored text in Source and Copy', (tester) async {
      final copied = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text']);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(_fill(const SvgBody(
        content: styled,
        fill: true,
        isStreaming: false,
        selectable: true,
      )));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy SVG'));
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(copied, [styled]);
      expect(
        find.textContaining('<style>.box', findRichText: true),
        findsOneWidget,
      );
    });
  });

  // On the VM there is no browser to draw the <img>: these tests report its
  // failure themselves, as a browser does for an SVG it cannot decode or a
  // CSP blocks, and run the real fallback to flutter_svg.
  group('in a browser', () {
    const browserFailure =
        'svg failed to render in the browser; drawing it with flutter_svg';

    setUp(() {
      debugSvgInBrowserOverride = true;
      addTearDown(() => debugSvgInBrowserOverride = null);
    });

    List<String> warnings(MemorySink sink) => [
          for (final r in sink.records)
            if (r.level == LogLevel.warning) r.message,
        ];

    testWidgets('draws a plain SVG with flutter_svg when the browser cannot',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      const plain = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><circle cx="5" cy="5" r="3"/></svg>';
      final body = _fill(const SvgBody(
        content: plain,
        fill: true,
        isStreaming: false,
        selectable: false,
      ));

      await tester.pumpWidget(body);
      expect(find.byType(BrowserSvgPicture), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      await _failBrowserPicture(tester);
      await _pumpLoaded(tester, body);

      expect(find.byType(BrowserSvgPicture), findsNothing);
      expect(find.text(_notice), findsNothing);
      expect(warnings(sink), [browserFailure]);
      final record =
          sink.records.singleWhere((r) => r.level == LogLevel.warning);
      // Logged whole: the browser's failure is fixed text, and a type name
      // in its place would be minified in a release build.
      expect(record.error, same(_browserRejection));
      expect(record.attributes['contentLength'], plain.length);
    });

    testWidgets('falls back to the SVG with its styles inlined',
        (tester) async {
      const styled = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
          'height="100"><style>.box { fill: #ff00ff; }</style>'
          '<rect class="box" width="100" height="100"/></svg>';
      final key = GlobalKey();
      final body = RepaintBoundary(
        key: key,
        child: _fill(const SvgBody(
          content: styled,
          fill: true,
          isStreaming: false,
          selectable: false,
        )),
      );

      await tester.pumpWidget(body);
      await _failBrowserPicture(tester);
      await _pumpLoaded(tester, body);

      expect(await _centrePixel(tester, key), const Color(0xFFFF00FF));
    });

    testWidgets('zoom keeps its SVG and can fall back after inline disposal',
        (tester) async {
      const styled = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
          'height="100"><style>.box { fill: #00ffff; }</style>'
          '<rect class="box" width="100" height="100"/></svg>';
      final content = ValueNotifier<String?>(styled);
      addTearDown(content.dispose);
      final inDialog = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(BrowserSvgPicture),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: content,
            builder: (context, value, _) => value == null
                ? const SizedBox.shrink()
                : SvgBody(
                    content: value,
                    fill: false,
                    isStreaming: false,
                    selectable: false,
                  ),
          ),
        ),
      ));
      await tester.tap(find.byType(BrowserSvgPicture), warnIfMissed: false);
      await tester.pumpAndSettle();

      content.value = _validSvg;
      await tester.pump();
      expect(tester.widget<BrowserSvgPicture>(inDialog).svg, styled);

      content.value = null;
      await tester.pump();
      expect(find.byType(BrowserSvgPicture), findsOneWidget);
      await _failBrowserPicture(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('a late failure cannot advance a replacement with the same SVG',
        (tester) async {
      const first = '<svg width="10" height="10"></svg>';
      const second = '<svg width="20" height="10"></svg>';
      Widget body(String content) => _inline(SvgBody(
            content: content,
            fill: false,
            isStreaming: false,
            selectable: false,
          ));
      final picture = find.byType(BrowserSvgPicture);

      await tester.pumpWidget(body(first));
      final old = tester.widget<BrowserSvgPicture>(picture);
      await tester.pumpWidget(body(second));
      await tester.pumpWidget(body(first));

      old.onFailed(StateError('late browser rejection'), null);
      await tester.pump();

      expect(tester.widget<BrowserSvgPicture>(picture).svg, first);
    });

    testWidgets('a dialog open when every attempt fails shows the notice',
        (tester) async {
      const content = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><rect width="10" height="10" fill="red"</svg>';

      await tester.pumpWidget(_inline(const SvgBody(
        content: content,
        fill: false,
        isStreaming: false,
        selectable: false,
      )));
      await tester.tap(find.byType(BrowserSvgPicture), warnIfMissed: false);
      await tester.pump();
      await _failBrowserPicture(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(_notice),
        ),
        findsOneWidget,
      );
    });

    testWidgets('zoom opens only after streaming ends', (tester) async {
      Widget body({required bool isStreaming}) => _inline(SvgBody(
            content: _validSvg,
            fill: false,
            isStreaming: isStreaming,
            selectable: false,
          ));
      final picture = find.byType(BrowserSvgPicture);

      await tester.pumpWidget(body(isStreaming: true));
      await tester.tap(picture, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await tester.pumpWidget(body(isStreaming: false));
      await tester.tap(picture, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('shows the notice when flutter_svg cannot draw it either',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      const content = 'not valid <svg in a browser either';

      await tester.pumpWidget(_fill(const SvgBody(
        content: content,
        fill: true,
        isStreaming: false,
        selectable: false,
      )));
      await _failBrowserPicture(tester);
      await tester.pumpAndSettle();

      expect(find.text(_notice), findsOneWidget);
      expect(warnings(sink), [browserFailure, 'svg content failed to render']);
    });

    testWidgets('draws a partial streaming SVG with flutter_svg only',
        (tester) async {
      await tester.pumpWidget(_fill(const SvgBody(
        content: '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
            'height="10"><circle',
        fill: true,
        isStreaming: true,
        selectable: false,
      )));

      expect(find.byType(BrowserSvgPicture), findsNothing);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('gives a whole streaming SVG to the browser', (tester) async {
      await tester.pumpWidget(_fill(const SvgBody(
        content: _validSvg,
        fill: true,
        isStreaming: true,
        selectable: false,
      )));

      expect(find.byType(BrowserSvgPicture), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });

  testWidgets('inline picture is capped at 400 px tall', (tester) async {
    const tall = '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
        'height="2000"><rect width="100" height="2000"/></svg>';
    await _pumpLoaded(
      tester,
      _inline(const SvgBody(
        content: tall,
        fill: false,
        isStreaming: false,
        selectable: false,
      )),
    );

    expect(
        tester.getSize(find.byType(SvgPicture)).height, lessThanOrEqualTo(400));
    expect(tester.getSize(find.byType(SvgPicture)).height, greaterThan(0));
  });
}

/// What the tests' browser reports for an image it would not draw.
final _browserRejection = StateError('the browser rejected the image');

/// Reports the browser's failure from every browser picture on screen, as
/// the browser does through each one's `<img>`, then pumps the frame that
/// draws the next attempt.
Future<void> _failBrowserPicture(WidgetTester tester) async {
  final pictures = tester
      .widgetList<BrowserSvgPicture>(find.byType(BrowserSvgPicture))
      .toList();
  for (final picture in pictures) {
    picture.onFailed(_browserRejection, null);
  }
  await tester.pump();
}

/// Pumps [widget] and checks flutter_svg has loaded its picture: in debug
/// builds it parses on the calling isolate, so the load completes within the
/// pump. A loaded picture is laid out in a [FittedBox]; until then flutter_svg
/// shows the placeholder.
///
/// flutter_svg prints a notice the first time in a process it meets an
/// element it does not draw (a `<style>` drawn as written); those are
/// captured, and anything else it prints fails the test.
Future<void> _pumpLoaded(WidgetTester tester, Widget widget) async {
  final printed = <String>[];
  final loaded = find.descendant(
    of: find.byType(SvgPicture),
    matching: find.byType(FittedBox),
  );
  await tester.runAsync(
    () => runZoned(
      () => tester.pumpWidget(widget),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => printed.add(line),
      ),
    ),
  );
  await tester.pump();
  expect(loaded, findsOneWidget, reason: 'flutter_svg did not load');
  expect(printed, everyElement(startsWith('unhandled element <style/>')));
}

/// The colour at the centre of the [SvgPicture] under the boundary at [key].
Future<Color?> _centrePixel(WidgetTester tester, GlobalKey key) =>
    _pixelAt(tester, key, tester.getCenter(find.byType(SvgPicture)));

Future<Color?> _pixelAt(WidgetTester tester, GlobalKey key, Offset centre) {
  return tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    final i = (centre.dy.round() * image.width + centre.dx.round()) * 4;
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  });
}
