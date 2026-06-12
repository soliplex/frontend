import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/connection_probe.dart';
import 'package:soliplex_frontend/src/modules/auth/consent_notice.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/connect_flow_rail.dart';

final _probeResult = ConnectionSuccess(
  serverUrl: Uri.parse('https://example.com'),
  providers: const [],
);

void main() {
  group('stepForConnectState', () {
    test('maps each ConnectState to its rail node', () {
      expect(stepForConnectState(const UrlInput()), ConnectStep.url);
      expect(stepForConnectState(const Probing()), ConnectStep.probe);
      expect(
        stepForConnectState(
          InsecureWarning(probeResult: _probeResult, providers: const []),
        ),
        ConnectStep.insecure,
      );
      expect(
        stepForConnectState(
          Consent(
            notice: const ConsentNotice(title: 'T', body: 'B'),
            probeResult: _probeResult,
            providers: const [],
          ),
        ),
        ConnectStep.consent,
      );
      expect(
        stepForConnectState(
          ProviderSelection(probeResult: _probeResult, providers: const []),
        ),
        ConnectStep.provider,
      );
      expect(stepForConnectState(const Authenticating()), ConnectStep.auth);
      expect(stepForConnectState(const Connected()), ConnectStep.connected);
    });
  });

  group('ConnectFlowRail', () {
    Widget host(ConnectStep current) => MaterialApp(
          home: Scaffold(
            body: Center(child: ConnectFlowRail(current: current)),
          ),
        );

    testWidgets('renders every step label', (tester) async {
      await tester.pumpWidget(host(ConnectStep.provider));
      for (final step in ConnectStep.values) {
        expect(find.text(step.label), findsOneWidget);
      }
    });

    testWidgets('marks every preceding step done, optional ones included',
        (tester) async {
      // Done-ness is purely positional: every node before `current` shows a
      // check. This documents a deliberate choice for the two branch-only
      // steps (insecure / consent) — the rail is handed only `current`, so it
      // cannot tell whether an optional branch was actually taken. A run takes
      // at most one of insecure/consent, yet at `provider` BOTH show a check.
      // We accept a stray check on a possibly-skipped step rather than leave a
      // genuinely-completed step unchecked.
      await tester.pumpWidget(host(ConnectStep.provider));

      // url, probe, insecure, consent all precede provider → four checks,
      // including both optional nodes.
      expect(
        find.byIcon(Icons.check),
        findsNWidgets(ConnectStep.provider.index),
      );
      expect(find.text(ConnectStep.insecure.label), findsOneWidget);
      expect(find.text(ConnectStep.consent.label), findsOneWidget);
    });

    testWidgets('shows no checks at the first step', (tester) async {
      await tester.pumpWidget(host(ConnectStep.url));
      expect(find.byIcon(Icons.check), findsNothing);
    });

    // Confirms the rail actually scrolls once its content is wider than the
    // visible space, rather than overflowing or shrinking to fit.
    testWidgets('scrolls horizontally when wider than its column',
        (tester) async {
      // A column far narrower than the seven-node strip's intrinsic width.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: ConnectFlowRail(current: ConnectStep.connected),
              ),
            ),
          ),
        ),
      );

      // No RenderFlex overflow was thrown while laying the strip out.
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: find.byType(ConnectFlowRail),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);

      // The content genuinely exceeds the visible width (there is room to
      // scroll), and starts pinned at the left edge.
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);

      // Dragging moves the strip — proving it scrolls rather than clips.
      await tester.drag(scrollable, const Offset(-80, 0));
      await tester.pump();
      expect(position.pixels, greaterThan(0));
    });
  });
}
