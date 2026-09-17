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
            usage: ContextUsage(measuredTokens: 4000, contextWindow: 8000),
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
        _host(const ContextGauge(usage: ContextUsage(estimatedTokens: 1234))),
      );

      // The draft is a fragment of a conversation nothing has counted,
      // so reciting it would present a part as the whole.
      final unmeasured = tester.getSemantics(find.byType(ContextGauge)).label;
      expect(unmeasured, isNot(contains('1234')));
      expect(unmeasured, contains('not been measured'));

      // A thread a run has measured, on a model that declares no window,
      // has a count and no percentage. Saying it has no reading denies
      // the very number in the same sentence.
      await tester.pumpWidget(
        _host(
          const ContextGauge(
            usage: ContextUsage(measuredTokens: 4321),
          ),
        ),
      );

      final measured = tester.getSemantics(find.byType(ContextGauge)).label;
      expect(measured, contains('4321 tokens'));
      expect(measured, isNot(contains('No context reading yet')));
    });

    testWidgets('keeps the composer row from jumping', (tester) async {
      // The ring appears and fills as a thread is measured; the slot it
      // sits in must not resize under the send button while it does.
      await tester.pumpWidget(
        _host(const ContextGauge(usage: ContextUsage())),
      );
      final hollow = tester.getSize(find.byType(ContextGauge));

      await tester.pumpWidget(
        _host(
          const ContextGauge(
            usage: ContextUsage(measuredTokens: 7600, contextWindow: 8000),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ContextGauge)), hollow);
    });
  });
}
