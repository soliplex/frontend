import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/content_frame.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ContentHeader', () {
    testWidgets('without a view shows no switch', (tester) async {
      await tester.pumpWidget(_host(const ContentHeader(
        label: 'dart',
        copyText: 'x',
        copyTooltip: 'Copy code',
      )));

      expect(find.byType(SegmentedButton<ContentView>), findsNothing);
      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('without a label shows no label', (tester) async {
      await tester.pumpWidget(_host(const ContentHeader(
        copyText: 'x',
        copyTooltip: 'Copy code',
      )));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('switch reports the tapped view', (tester) async {
      ContentView? reported;
      await tester.pumpWidget(_host(ContentHeader(
        copyText: 'x',
        copyTooltip: 'Copy SVG',
        view: ContentView.rendered,
        renderedLabel: 'Preview',
        onViewChanged: (view) => reported = view,
      )));

      expect(find.text('Preview'), findsOneWidget);
      await tester.tap(find.text('Source'));

      expect(reported, ContentView.source);
    });

    testWidgets('copy uses the tooltip', (tester) async {
      await tester.pumpWidget(_host(const ContentHeader(
        copyText: 'x',
        copyTooltip: 'Copy SVG',
      )));

      expect(find.byTooltip('Copy SVG'), findsOneWidget);
    });
  });

  testWidgets('RenderFailureNotice shows its message', (tester) async {
    await tester.pumpWidget(_host(const RenderFailureNotice(message: 'Oops')));

    expect(find.text('Oops'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  group('ContentFrame', () {
    testWidgets('inline lays header, notice and body out in order',
        (tester) async {
      await tester.pumpWidget(_host(const SingleChildScrollView(
        child: ContentFrame(
          header: Text('header'),
          notice: Text('notice'),
          body: Text('body'),
          fill: false,
        ),
      )));

      final tops = [
        for (final text in ['header', 'notice', 'body'])
          tester.getTopLeft(find.text(text)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tops.toSet(), hasLength(3));
    });

    testWidgets('fill scrolls a tall body and keeps the header on screen',
        (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        height: 300,
        child: ContentFrame(
          header: Text('header'),
          body: SizedBox(height: 2000, child: Text('body')),
          fill: true,
        ),
      )));

      await tester.drag(find.byType(ContentFrame), const Offset(0, -500));
      await tester.pump();

      expect(find.text('header').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('body')).dy, lessThan(0));
    });

    testWidgets('fill with scrollBody false gives the body finite height',
        (tester) async {
      double? maxHeight;
      await tester.pumpWidget(_host(SizedBox(
        height: 300,
        child: ContentFrame(
          header: const Text('header'),
          body: LayoutBuilder(builder: (context, constraints) {
            maxHeight = constraints.maxHeight;
            return const SizedBox.expand();
          }),
          fill: true,
          scrollBody: false,
        ),
      )));

      expect(maxHeight, isNotNull);
      expect(maxHeight!.isFinite, isTrue);
    });
  });
}
