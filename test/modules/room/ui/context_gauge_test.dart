import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
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
      expect(
        semantics.label,
        'Context usage: 50 percent of the context window.',
      );
    });

    testWidgets('reads out "about" when the reading includes an estimate',
        (tester) async {
      Future<String?> labelFor(ContextUsage usage) async {
        await tester.pumpWidget(_host(ContextGauge(usage: usage)));
        return tester.getSemantics(find.byType(ContextGauge)).label;
      }

      expect(
        await labelFor(
          const ContextUsage(
            measuredTokens: 4000,
            estimatedTokens: 320,
            contextWindow: 8000,
          ),
        ),
        'Context usage: about 54 percent of the context window.',
      );
      expect(
        await labelFor(
          const ContextUsage(measuredTokens: 4000, draftTokens: 321),
        ),
        'Context usage: about 4321 tokens; no percentage available.',
      );
    });

    testWidgets('says so rather than inventing a denominator', (tester) async {
      // A room with no reported window must not be shown as a percentage;
      // a guessed limit would make a wrong number look authoritative.
      await tester.pumpWidget(
        _host(const ContextGauge(usage: ContextUsage(estimatedTokens: 1234))),
      );

      // The estimate is a fragment of a conversation nothing has counted,
      // so reciting it would present a part as the whole.
      final unmeasured = tester.getSemantics(find.byType(ContextGauge)).label;
      expect(unmeasured, isNot(contains('1234')));
      expect(unmeasured, 'Context usage has not been measured yet.');

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
      expect(
        measured,
        'Context usage: 4321 tokens; no percentage available.',
      );
    });

    group('the ring colour', () {
      Future<BuildContext> pumpAt(
        WidgetTester tester,
        int tokens,
      ) async {
        await tester.pumpWidget(
          _host(
            ContextGauge(
              usage: ContextUsage(measuredTokens: tokens, contextWindow: 100),
            ),
          ),
        );
        return tester.element(find.byType(ContextGauge));
      }

      RenderObject ring(WidgetTester tester) => tester.renderObject(
            find.descendant(
              of: find.byType(ContextGauge),
              matching: find.byType(CustomPaint),
            ),
          );

      testWidgets('is the danger colour from 90%', (tester) async {
        final context = await pumpAt(tester, 90);

        expect(
            ring(tester),
            paints
              ..circle()
              ..arc(color: context.danger));
      });

      testWidgets('is the warning colour from 80% up to 90%', (tester) async {
        final context = await pumpAt(tester, 89);

        expect(
            ring(tester),
            paints
              ..circle()
              ..arc(color: context.warning));
      });

      testWidgets('is the primary colour below 80%', (tester) async {
        final context = await pumpAt(tester, 79);

        expect(
          ring(tester),
          paints
            ..circle()
            ..arc(color: Theme.of(context).colorScheme.primary),
        );
      });
    });

    testWidgets('says over 100 percent past the window, estimate or not',
        (tester) async {
      Future<String> labelFor(ContextUsage usage) async {
        await tester.pumpWidget(_host(ContextGauge(usage: usage)));
        return tester.getSemantics(find.byType(ContextGauge)).label;
      }

      const over = 'Context usage: over 100 percent of the context window.';
      expect(
        await labelFor(
          const ContextUsage(
            measuredTokens: 16000,
            estimatedTokens: 1000,
            contextWindow: 16384,
          ),
        ),
        over,
      );
      expect(
        await labelFor(
          const ContextUsage(measuredTokens: 20000, contextWindow: 16384),
        ),
        over,
      );
    });

    group('the tooltip', () {
      Future<String> tooltipFor(WidgetTester tester, ContextUsage usage) async {
        await tester.pumpWidget(_host(ContextGauge(usage: usage)));
        return tester.widget<Tooltip>(find.byType(Tooltip)).message!;
      }

      testWidgets('has no ~ when every token was counted', (tester) async {
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(measuredTokens: 4000, contextWindow: 8000),
          ),
          '50% of context used',
        );
        expect(
          await tooltipFor(tester, const ContextUsage(measuredTokens: 4321)),
          '4321 tokens used',
        );
      });

      testWidgets('starts with ~ when the reading includes an estimate',
          (tester) async {
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(
              measuredTokens: 3000,
              estimatedTokens: 500,
              draftTokens: 500,
              contextWindow: 8000,
            ),
          ),
          '~50% of context used',
        );
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(measuredTokens: 4000, draftTokens: 321),
          ),
          '~4321 tokens used',
        );
      });

      testWidgets('says over 100% past the window, estimate or not',
          (tester) async {
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(
              measuredTokens: 16000,
              estimatedTokens: 1000,
              contextWindow: 16384,
            ),
          ),
          '>100% of context used',
        );
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(measuredTokens: 20000, contextWindow: 16384),
          ),
          '>100% of context used',
        );
      });

      testWidgets('says 100% at exactly the window', (tester) async {
        expect(
          await tooltipFor(
            tester,
            const ContextUsage(measuredTokens: 16384, contextWindow: 16384),
          ),
          '100% of context used',
        );
      });
    });
  });
}
