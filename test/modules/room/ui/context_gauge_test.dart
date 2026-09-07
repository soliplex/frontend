import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/ui/context_breakdown_sheet.dart';
import 'package:soliplex_frontend/src/modules/room/ui/context_gauge.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ContextGauge', () {
    testWidgets('reads out a percentage when a window is declared',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const ContextGauge(
            usage: ContextUsage(
              tokens: 4000,
              byKind: {},
              contextWindow: 8000,
              isProvisional: false,
              isExact: true,
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ContextGauge));
      expect(semantics.label, contains('50 percent'));
    });

    testWidgets('says so rather than inventing a denominator', (tester) async {
      // A room with no declared window must not be shown as a percentage;
      // a guessed limit would make a wrong number look authoritative.
      await tester.pumpWidget(
        _host(
          const ContextGauge(
            usage: ContextUsage(tokens: 1234, byKind: {}),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ContextGauge));
      expect(semantics.label, contains('1234 tokens'));
      expect(semantics.label, contains('No context window'));
    });

    testWidgets('offers a full-size tap target around a small ring',
        (tester) async {
      await tester.pumpWidget(
        _host(
          ContextGauge(
            usage: const ContextUsage(tokens: 10, byKind: {}),
            onTap: () {},
          ),
        ),
      );

      expect(tester.getSize(find.byType(ContextGauge)).height, 44);
    });

    testWidgets('is inert without a callback', (tester) async {
      await tester.pumpWidget(
        _host(
          const ContextGauge(usage: ContextUsage(tokens: 10, byKind: {})),
        ),
      );

      await tester.tap(find.byType(ContextGauge));
      await tester.pump();
      // No exception: the control simply does nothing when it has no
      // breakdown to open.
    });

    testWidgets('renders in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(
            const ContextGauge(
              usage: ContextUsage(
                tokens: 7600,
                byKind: {},
                contextWindow: 8000,
              ),
            ),
            brightness: brightness,
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('ContextBreakdownDialog', () {
    const usage = ContextUsage(
      tokens: 5200,
      byKind: {
        SegmentKind.userText: 1200,
        SegmentKind.toolResult: 3000,
        SegmentKind.overhead: 1000,
      },
      contextWindow: 8000,
      isProvisional: false,
      isExact: true,
    );

    testWidgets('lists each contributor with its token count', (tester) async {
      await tester.pumpWidget(
        _host(const ContextBreakdownDialog(usage: usage)),
      );

      expect(find.text('5200 tokens'), findsOneWidget);
      expect(find.text('Tool results'), findsOneWidget);
      expect(find.text('3000'), findsOneWidget);
      expect(find.textContaining('65%'), findsOneWidget);
    });

    testWidgets('omits contributors that cost nothing', (tester) async {
      await tester.pumpWidget(
        _host(const ContextBreakdownDialog(usage: usage)),
      );

      expect(find.text('Assistant replies'), findsNothing);
    });

    testWidgets('names every reason a reading is approximate', (tester) async {
      await tester.pumpWidget(
        _host(
          const ContextBreakdownDialog(
            usage: ContextUsage(
              tokens: 100,
              byKind: {SegmentKind.userText: 100},
              hasUncountableContent: true,
            ),
          ),
        ),
      );

      expect(find.textContaining('Still calibrating'), findsOneWidget);
      expect(find.textContaining('no exact tokenizer'), findsOneWidget);
      expect(find.textContaining('attachments'), findsOneWidget);
    });

    testWidgets('handles a thread nothing has been counted for yet',
        (tester) async {
      await tester.pumpWidget(
        _host(const ContextBreakdownDialog(usage: ContextUsage.unknown())),
      );

      expect(find.text('Nothing counted yet.'), findsOneWidget);
    });
  });
}
