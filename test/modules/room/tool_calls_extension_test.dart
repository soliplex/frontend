import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart' show ToolCallStatus;

import 'package:soliplex_frontend/src/modules/room/tool_calls_extension.dart';

// ---------------------------------------------------------------------------
// Fake session
// ---------------------------------------------------------------------------

class _FakeSession implements AgentSession {
  final Signal<ExecutionEvent?> _event = Signal(null);

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => _event;

  void emit(ExecutionEvent event) => _event.value = event;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('ToolCallsExtension', () {
    late ToolCallsExtension ext;
    late _FakeSession session;

    setUp(() async {
      ext = ToolCallsExtension();
      session = _FakeSession();
      await ext.onAttach(session);
    });

    tearDown(() => ext.onDispose());

    test('initial state is empty list', () {
      expect(ext.state, isEmpty);
    });

    test('ClientToolExecuting adds executing entry (client-side)', () {
      session.emit(const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
      ));

      expect(ext.state, hasLength(1));
      expect(ext.state.first.toolCallId, 'tc-1');
      expect(ext.state.first.toolName, 'my_tool');
      expect(ext.state.first.status, ToolCallStatus.executing);
      expect(ext.state.first.isClientSide, isTrue);
    });

    test('ServerToolCallStarted adds executing entry (server-side)', () {
      session.emit(const ServerToolCallStarted(
        toolCallId: 'tc-s1',
        toolName: 'server_tool',
      ));

      expect(ext.state, hasLength(1));
      expect(ext.state.first.isClientSide, isFalse);
      expect(ext.state.first.status, ToolCallStatus.executing);
    });

    test('ClientToolCompleted updates status on existing entry', () {
      session.emit(const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
      ));
      session.emit(const ClientToolCompleted(
        toolCallId: 'tc-1',
        status: ToolCallStatus.completed,
        result: 'result',
      ));

      expect(ext.state.first.status, ToolCallStatus.completed);
    });

    test('ServerToolCallCompleted marks entry completed', () {
      session.emit(const ServerToolCallStarted(
        toolCallId: 'tc-s1',
        toolName: 'server_tool',
      ));
      session.emit(const ServerToolCallCompleted(
        toolCallId: 'tc-s1',
        result: 'done',
      ));

      expect(ext.state.first.status, ToolCallStatus.completed);
    });

    test('multiple tool calls tracked independently', () {
      session.emit(const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'tool_a',
      ));
      session.emit(const ServerToolCallStarted(
        toolCallId: 'tc-2',
        toolName: 'tool_b',
      ));

      expect(ext.state, hasLength(2));
      expect(ext.state.map((e) => e.toolCallId), containsAll(['tc-1', 'tc-2']));
    });

    test('completion of unknown id is a no-op', () {
      session.emit(const ServerToolCallCompleted(
        toolCallId: 'unknown',
        result: 'x',
      ));
      expect(ext.state, isEmpty);
    });

    test('upsert on existing id updates status rather than appending', () {
      session.emit(const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
      ));
      session.emit(const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
      ));

      expect(ext.state, hasLength(1));
    });

    test('preserves insertion order', () {
      for (var i = 1; i <= 3; i++) {
        session.emit(ServerToolCallStarted(
          toolCallId: 'tc-$i',
          toolName: 'tool_$i',
        ));
      }

      expect(
        ext.state.map((e) => e.toolCallId).toList(),
        ['tc-1', 'tc-2', 'tc-3'],
      );
    });

    test('stateSignal notifies on change', () {
      final counts = <int>[];
      ext.stateSignal.subscribe((v) => counts.add(v.length));

      session.emit(const ServerToolCallStarted(
        toolCallId: 'tc-1',
        toolName: 't',
      ));
      session.emit(const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'done',
      ));

      expect(counts, contains(1));
    });

    test('namespace is tool_calls', () => expect(ext.namespace, 'tool_calls'));
    test('priority is 5', () => expect(ext.priority, 5));
    test('tools is empty', () => expect(ext.tools, isEmpty));

    test('onDispose unsubscribes — emitting after dispose does not throw', () {
      ext.onDispose();
      expect(
        () => session.emit(const ServerToolCallStarted(
          toolCallId: 'post',
          toolName: 't',
        )),
        returnsNormally,
      );
    });
  });

  group('ToolCallEntry', () {
    const entry = ToolCallEntry(
      toolCallId: 'tc-1',
      toolName: 'my_tool',
      status: ToolCallStatus.executing,
      isClientSide: true,
    );

    test('copyWith updates status', () {
      final updated = entry.copyWith(status: ToolCallStatus.completed);
      expect(updated.status, ToolCallStatus.completed);
      expect(updated.toolCallId, entry.toolCallId);
      expect(updated.isClientSide, entry.isClientSide);
    });

    test('copyWith without args returns equivalent entry', () {
      final copy = entry.copyWith();
      expect(copy, equals(entry));
    });

    test('equality considers all fields', () {
      const same = ToolCallEntry(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        status: ToolCallStatus.executing,
        isClientSide: true,
      );
      const different = ToolCallEntry(
        toolCallId: 'tc-1',
        toolName: 'my_tool',
        status: ToolCallStatus.completed,
        isClientSide: true,
      );
      expect(entry, equals(same));
      expect(entry, isNot(equals(different)));
    });
  });
}
