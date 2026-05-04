import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/human_approval_extension.dart';
import 'package:soliplex_frontend/src/modules/room/ui/approval_handler.dart';

ApprovalRequest _request({String toolCallId = 'tc-1'}) => ApprovalRequest(
      toolCallId: toolCallId,
      toolName: 'send_email',
      arguments: const {'to': 'a@b.c'},
      rationale: 'send a message',
    );

Widget _harness({
  required ReadonlySignal<ApprovalRequest?> pendingApproval,
  required void Function(ApprovalRequest, bool) onRespond,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ApprovalHandler(
          pendingApproval: pendingApproval,
          onRespond: onRespond,
        ),
      ),
    );

void main() {
  testWidgets('shows dialog when signal transitions null → request',
      (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    expect(find.text('Tool Approval Required'), findsNothing);

    pending.value = _request();
    await tester.pumpAndSettle();

    expect(find.text('Tool Approval Required'), findsOneWidget);
    expect(find.text('send_email'), findsOneWidget);
    expect(find.text('send a message'), findsOneWidget);
  });

  testWidgets('Allow tap forwards (request, true)', (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    final req = _request();
    pending.value = req;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(responses, [(req, true)]);
    expect(find.text('Tool Approval Required'), findsNothing);
  });

  testWidgets('Deny tap forwards (request, false)', (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    final req = _request();
    pending.value = req;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(responses, [(req, false)]);
  });

  testWidgets('does not stack a second dialog when same request re-emits',
      (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    final req = _request();
    pending.value = req;
    await tester.pumpAndSettle();

    pending.value = req;
    await tester.pump();

    expect(find.text('Tool Approval Required'), findsOneWidget);
  });

  testWidgets('replaces existing dialog when a different request arrives',
      (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    pending.value = _request(toolCallId: 'tc-A');
    await tester.pumpAndSettle();
    expect(find.text('Tool Approval Required'), findsOneWidget);

    final reqB = _request(toolCallId: 'tc-B');
    pending.value = reqB;
    await tester.pumpAndSettle();

    expect(find.text('Tool Approval Required'), findsOneWidget);
    // No spurious response was forwarded for the superseded request.
    expect(responses, isEmpty);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    // Only the new request's response is forwarded.
    expect(responses, [(reqB, true)]);
    expect(find.text('Tool Approval Required'), findsNothing);
  });

  testWidgets('rapid same-frame requests do not stack dialogs', (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    // Two requests arrive in the same frame, before the post-frame
    // callback for the first one runs. The handler must show only the
    // most recent one, not stack two dialogs.
    pending.value = _request(toolCallId: 'tc-A');
    pending.value = _request(toolCallId: 'tc-B');
    await tester.pumpAndSettle();

    expect(find.text('Tool Approval Required'), findsOneWidget);
    expect(responses, isEmpty);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(responses, hasLength(1));
    expect(responses.single.$1.toolCallId, 'tc-B');
  });

  testWidgets('signal going null while dialog showing dismisses the dialog',
      (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    pending.value = _request();
    await tester.pumpAndSettle();
    expect(find.text('Tool Approval Required'), findsOneWidget);

    // Extension cleared the request (e.g., session cancelled externally).
    pending.value = null;
    await tester.pumpAndSettle();

    expect(find.text('Tool Approval Required'), findsNothing);
    // No synthetic response was forwarded — the extension already resolved.
    expect(responses, isEmpty);
  });

  testWidgets('unmounting while dialog showing dismisses without responding',
      (tester) async {
    final pending = Signal<ApprovalRequest?>(null);
    final responses = <(ApprovalRequest, bool)>[];
    await tester.pumpWidget(
      _harness(
        pendingApproval: pending,
        onRespond: (r, a) => responses.add((r, a)),
      ),
    );

    pending.value = _request();
    await tester.pumpAndSettle();
    expect(find.text('Tool Approval Required'), findsOneWidget);

    // Replace the entire harness — the ApprovalHandler unmounts.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(find.text('Tool Approval Required'), findsNothing);
    // The extension's pending request stays live; no synthetic response is
    // forwarded so the user can still answer if the screen re-attaches.
    expect(responses, isEmpty);
  });
}
