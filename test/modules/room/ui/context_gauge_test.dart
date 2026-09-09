import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/ui/context_gauge.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ContextGauge', () {
    testWidgets('reads out a percentage when a window is reported',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const ContextGauge(
            usage: ContextUsage(
              tokens: 4000,
              contextWindow: 8000,
              isExact: true,
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ContextGauge));
      expect(semantics.label, contains('50 percent'));
    });

    testWidgets('says so rather than inventing a denominator', (tester) async {
      // A room with no reported window must not be shown as a percentage;
      // a guessed limit would make a wrong number look authoritative.
      await tester.pumpWidget(
        _host(const ContextGauge(usage: ContextUsage(tokens: 1234))),
      );

      final semantics = tester.getSemantics(find.byType(ContextGauge));
      expect(semantics.label, contains('1234 tokens'));
      expect(semantics.label, contains('No context window'));
    });

    testWidgets('reserves a stable slot in the composer row', (tester) async {
      await tester.pumpWidget(
        _host(const ContextGauge(usage: ContextUsage(tokens: 10))),
      );

      expect(tester.getSize(find.byType(ContextGauge)).height, 44);
    });

    testWidgets('reports rather than acts', (tester) async {
      // There is nothing behind the ring to open, so it must not
      // announce itself as a button or offer a tap affordance.
      await tester.pumpWidget(
        _host(const ContextGauge(usage: ContextUsage(tokens: 10))),
      );

      final semantics = tester.getSemantics(find.byType(ContextGauge));
      expect(
        semantics.flagsCollection.isButton,
        isFalse,
        reason: 'the gauge is a status readout, not a control',
      );
      expect(find.byType(InkResponse), findsNothing);
    });

    testWidgets('renders in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(
            const ContextGauge(
              usage: ContextUsage(tokens: 7600, contextWindow: 8000),
            ),
            brightness: brightness,
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
