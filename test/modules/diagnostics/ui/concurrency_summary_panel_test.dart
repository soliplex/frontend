import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/concurrency_summary_panel.dart';

import '../../../helpers/http_event_factories.dart';

Future<void> _pump(
  WidgetTester tester,
  List<ConcurrencyWaitEvent> events,
) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ConcurrencySummaryPanel(events: events))),
  );
}

void main() {
  group('ConcurrencySummaryPanel', () {
    testWidgets('renders nothing when events list is empty', (tester) async {
      await _pump(tester, const []);

      // With an empty list the panel collapses to a zero-size placeholder.
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      expect(find.textContaining('queued'), findsNothing);
    });

    testWidgets('renders totals, peak slots, and max depth', (tester) async {
      await _pump(tester, [
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-1',
          waitDuration: Duration.zero,
          queueDepthAtEnqueue: 0,
          slotsInUseAfterAcquire: 1,
        ),
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-2',
          waitDuration: const Duration(milliseconds: 200),
          queueDepthAtEnqueue: 3,
          slotsInUseAfterAcquire: 4,
        ),
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-3',
          waitDuration: const Duration(milliseconds: 100),
          queueDepthAtEnqueue: 2,
          slotsInUseAfterAcquire: 5,
        ),
      ]);

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.text('queued 2 of 3'), findsOneWidget);
      expect(find.text('peak slots 5 / max depth 3'), findsOneWidget);
      expect(find.text('max 200ms'), findsOneWidget);
    });

    testWidgets('computes avg wait across queued events only', (tester) async {
      await _pump(tester, [
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-fast',
          waitDuration: Duration.zero,
        ),
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-slow',
          waitDuration: const Duration(milliseconds: 100),
        ),
      ]);

      // The Duration.zero event must be excluded from the average; otherwise
      // the mean would be 50ms instead of 100ms.
      expect(find.text('avg 100ms'), findsOneWidget);
    });

    testWidgets('omits avg when nothing was queued', (tester) async {
      await _pump(tester, [
        createConcurrencyWaitEvent(
          acquisitionId: 'acq-fast',
          waitDuration: Duration.zero,
        ),
      ]);

      expect(find.text('queued 0 of 1'), findsOneWidget);
      expect(find.textContaining('avg'), findsNothing);
    });
  });
}
