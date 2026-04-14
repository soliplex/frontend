import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  // ── requiresApproval flag ─────────────────────────────────────────────────

  group('ClientTool.requiresApproval', () {
    test('defaults to false', () {
      final tool = ClientTool(
        definition: const Tool(name: 'render_widget', description: ''),
        executor: (_, __) async => '',
      );
      expect(tool.requiresApproval, isFalse);
    });

    test('can be set to true', () {
      final tool = ClientTool(
        definition: const Tool(name: 'execute_python', description: ''),
        executor: (_, __) async => '',
        requiresApproval: true,
      );
      expect(tool.requiresApproval, isTrue);
    });

    test('ClientTool.simple defaults to false', () {
      final tool = ClientTool.simple(
        name: 'get_location',
        description: 'Returns GPS coordinates.',
        executor: (_, __) async => '{"lat": 37.7749, "lng": -122.4194}',
      );
      expect(tool.requiresApproval, isFalse);
    });
  });

  // ── Approval categories ───────────────────────────────────────────────────
  //
  // Three tool categories with distinct approval semantics:
  //
  // 1. execute_python — requiresApproval: true
  //    The agent framework suspends execution and emits PendingApprovalRequest
  //    on AgentSession.pendingApproval. No code runs until the UI calls
  //    session.approveToolCall() or session.denyToolCall().
  //
  // 2. get_location — requiresApproval: false
  //    The agent framework skips its gate entirely. The OS (iOS/macOS/Web)
  //    shows its own "Allow location access?" dialog inside the executor.
  //    The agent sees the result (or a permission error); it never sees the
  //    dialog.
  //
  // 3. render_widget — requiresApproval: false
  //    Fire-and-forget. No approval at any level. The executor emits a signal
  //    for the Flutter layer and returns "" immediately. The agent continues.

  group('approval categories', () {
    test(
      'execute_python: requiresApproval true — agent gate fires',
      () {
        final tool = ClientTool(
          definition: const Tool(name: 'execute_python', description: ''),
          requiresApproval: true,
          executor: (_, __) async => '42',
        );
        expect(
          tool.requiresApproval,
          isTrue,
          reason: 'execute_python suspends via AgentSession.pendingApproval '
              'until session.approveToolCall() is called.',
        );
      },
    );

    test(
      'get_location: requiresApproval false — OS handles consent',
      () {
        final tool = ClientTool.simple(
          name: 'get_location',
          description: 'Returns GPS coordinates.',
          // requiresApproval defaults to false —
          // OS dialog fires inside executor
          executor: (_, __) async => '{"lat": 37.7749, "lng": -122.4194}',
        );
        expect(
          tool.requiresApproval,
          isFalse,
          reason: 'get_location skips the agent gate. The OS shows its own '
              '"Allow location?" dialog inside the executor. The agent '
              'framework is not involved.',
        );
      },
    );

    test(
      'render_widget: requiresApproval false — no approval at any level',
      () {
        final tool = ClientTool.simple(
          name: 'render_widget',
          description: 'Renders a UI widget.',
          // requiresApproval defaults to false — fire-and-forget
          executor: (_, __) async => '',
        );
        expect(
          tool.requiresApproval,
          isFalse,
          reason: 'render_widget is fire-and-forget. The agent receives "" '
              'and continues. No gate, no OS dialog.',
        );
      },
    );
  });

  // ── PendingApprovalRequest ────────────────────────────────────────────────

  group('PendingApprovalRequest', () {
    test('carries toolCallId, toolName, and arguments', () {
      const req = PendingApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'execute_python',
        arguments: {'code': 'print("hello")'},
      );
      expect(req.toolCallId, equals('tc-1'));
      expect(req.toolName, equals('execute_python'));
      expect(req.arguments, equals({'code': 'print("hello")'}));
    });
  });

  // ── platformConsentNote ───────────────────────────────────────────────────
  //
  // Non-blocking consent notices for platform-conditional permission dialogs
  // (e.g. clipboard read on web triggers a browser prompt; on native it does
  // not). The callback returns null when no notice is needed so the session
  // emits nothing.

  group('ClientTool.platformConsentNote', () {
    test('defaults to null', () {
      final tool = ClientTool.simple(
        name: 'get_device_info',
        description: 'Returns device info.',
        executor: (_, __) async => '{}',
      );
      expect(tool.platformConsentNote, isNull);
    });

    test('can be set and returns the expected string', () {
      const note = 'Clipboard read requires browser permission on web.';
      final tool = ClientTool.simple(
        name: 'get_clipboard',
        description: 'Reads clipboard text.',
        executor: (_, __) async => '',
        platformConsentNote: () => note,
      );
      expect(tool.platformConsentNote?.call(), equals(note));
    });

    test('callback may return null to suppress the notice', () {
      final tool = ClientTool.simple(
        name: 'get_clipboard',
        description: 'Reads clipboard text.',
        executor: (_, __) async => '',
        // Simulates native path: no browser permission needed.
        platformConsentNote: () => null,
      );
      expect(tool.platformConsentNote?.call(), isNull);
    });
  });

  // ── PlatformConsentNotice event ───────────────────────────────────────────

  group('PlatformConsentNotice', () {
    test('carries toolCallId, toolName, and note', () {
      const event = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'Clipboard read requires browser permission on web.',
      );
      expect(event.toolCallId, equals('tc-2'));
      expect(event.toolName, equals('get_clipboard'));
      expect(
        event.note,
        equals('Clipboard read requires browser permission on web.'),
      );
    });

    test('equality compares all fields', () {
      const a = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'note',
      );
      const b = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'note',
      );
      const c = PlatformConsentNotice(
        toolCallId: 'tc-2',
        toolName: 'get_clipboard',
        note: 'different note',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
