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

    testWidgets('marks every preceding step with a check', (tester) async {
      // At the provider step, url/probe/insecure/consent precede it.
      await tester.pumpWidget(host(ConnectStep.provider));
      expect(
        find.byIcon(Icons.check),
        findsNWidgets(ConnectStep.provider.index),
      );
    });

    testWidgets('shows no checks at the first step', (tester) async {
      await tester.pumpWidget(host(ConnectStep.url));
      expect(find.byIcon(Icons.check), findsNothing);
    });
  });
}
