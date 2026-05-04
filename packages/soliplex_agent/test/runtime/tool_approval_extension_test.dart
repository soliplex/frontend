import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockAgentSession extends Mock implements AgentSession {}

class _Approval1 extends ToolApprovalExtension {
  int attachCount = 0;
  int disposeCount = 0;

  @override
  Future<void> onAttach(AgentSession session) async {
    attachCount++;
  }

  @override
  void onDispose() {
    disposeCount++;
  }

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async =>
      true;
}

class _Approval2 extends ToolApprovalExtension {
  int attachCount = 0;
  int disposeCount = 0;

  @override
  Future<void> onAttach(AgentSession session) async {
    attachCount++;
  }

  @override
  void onDispose() {
    disposeCount++;
  }

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async =>
      false;
}

void main() {
  group('ToolApprovalExtension namespace', () {
    test('subclasses share the locked "tool_approval" namespace', () {
      expect(_Approval1().namespace, 'tool_approval');
      expect(_Approval2().namespace, 'tool_approval');
    });

    test(
      'registering two ToolApprovalExtensions drops the duplicate, logs an '
      'error, and never attaches the dropped instance',
      () async {
        final logger = _MockLogger();
        final first = _Approval1();
        final second = _Approval2();
        final coordinator = SessionCoordinator(
          [first, second],
          logger: logger,
        );

        verify(
          () => logger.error(
            any(that: contains('tool_approval')),
          ),
        ).called(1);

        expect(coordinator.getExtension<ToolApprovalExtension>(), same(first));

        // The dropped duplicate is gone — its lifecycle hooks must never run.
        await coordinator.attachAll(_MockAgentSession());
        coordinator.disposeAll();

        expect(first.attachCount, 1);
        expect(first.disposeCount, 1);
        expect(second.attachCount, 0);
        expect(second.disposeCount, 0);
      },
    );
  });
}
