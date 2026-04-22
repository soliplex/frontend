import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/human_approval_extension.dart';

class _FakeSession implements AgentSession {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('HumanApprovalExtension', () {
    late HumanApprovalExtension ext;

    setUp(() async {
      ext = HumanApprovalExtension();
      await ext.onAttach(_FakeSession());
    });

    tearDown(() => ext.onDispose());

    test('initial state is null', () {
      expect(ext.state, isNull);
    });

    test('requestApproval sets state to ApprovalRequest', () async {
      unawaited(ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {'x': 1},
        rationale: 'doing stuff',
      ));

      expect(ext.state, isNotNull);
      expect(ext.state!.toolCallId, 'tc-1');
      expect(ext.state!.toolName, 'my_tool');
      expect(ext.state!.rationale, 'doing stuff');
    });

    test('respond(true) resolves future with true', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      );

      ext.respond(true);

      expect(await future, isTrue);
    });

    test('respond(false) resolves future with false', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      );

      ext.respond(false);

      expect(await future, isFalse);
    });

    test('respond clears state to null', () async {
      unawaited(ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      ));

      ext.respond(true);

      expect(ext.state, isNull);
    });

    test('new requestApproval denies stale pending with false', () async {
      final first = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'tool_a',
        arguments: {},
        rationale: 'first',
      );

      unawaited(ext.requestApproval(
        toolCallId: 'tc-2',
        toolName: 'tool_b',
        arguments: {},
        rationale: 'second',
      ));

      expect(await first, isFalse);
    });

    test('new requestApproval updates state to new request', () async {
      unawaited(ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'tool_a',
        arguments: {},
        rationale: 'first',
      ));
      unawaited(ext.requestApproval(
        toolCallId: 'tc-2',
        toolName: 'tool_b',
        arguments: {},
        rationale: 'second',
      ));

      expect(ext.state!.toolCallId, 'tc-2');
    });

    test('onDispose auto-denies pending request with false', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      );

      ext.onDispose();

      expect(await future, isFalse);
    });

    test('respond when no pending is a no-op', () {
      expect(() => ext.respond(true), returnsNormally);
    });

    test('stateSignal notifies when request arrives', () {
      final received = <ApprovalRequest?>[];
      ext.stateSignal.subscribe((v) => received.add(v));

      unawaited(ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'r',
      ));

      expect(received.where((v) => v != null), isNotEmpty);
    });

    test('stateSignal notifies null after respond', () async {
      final nullCount = <int>[];
      ext.stateSignal.subscribe((v) {
        if (v == null) nullCount.add(1);
      });

      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'r',
      );
      ext.respond(true);
      await future;

      expect(nullCount, isNotEmpty);
    });

    test('namespace is human_approval', () => expect(ext.namespace, 'human_approval'));
    test('priority is 30', () => expect(ext.priority, 30));
    test('tools is empty', () => expect(ext.tools, isEmpty));

    test('onAttach is a no-op (does not throw)', () async {
      final ext2 = HumanApprovalExtension();
      expect(() async => ext2.onAttach(_FakeSession()), returnsNormally);
      ext2.onDispose();
    });
  });

  group('ApprovalRequest', () {
    const r = ApprovalRequest(
      toolCallId: 'tc-1',
      toolName: 'my_tool',
      arguments: {'x': 1},
      rationale: 'reason',
    );

    test('equality considers toolCallId, toolName, rationale', () {
      const same = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {'y': 2},
        rationale: 'reason',
      );
      const different = ApprovalRequest(
        toolCallId: 'tc-2',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      );
      expect(r, equals(same));
      expect(r, isNot(equals(different)));
    });

    test('hashCode consistent with equality', () {
      const same = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        arguments: {},
        rationale: 'reason',
      );
      expect(r.hashCode, same.hashCode);
    });
  });
}
