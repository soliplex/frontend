import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/tool_calls_extension.dart';

/// Minimal AgentSession fake that only exposes [lastExecutionEvent].
class _FakeSession implements AgentSession {
  final Signal<ExecutionEvent?> events = Signal<ExecutionEvent?>(null);

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => events;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_FakeSession.${invocation.memberName}',
      );
}

void main() {
  late _FakeSession session;
  late ToolCallsExtension ext;

  setUp(() async {
    session = _FakeSession();
    ext = ToolCallsExtension();
    await ext.onAttach(session);
  });

  tearDown(() => ext.onDispose());

  test('starts empty after onAttach', () {
    expect(ext.state, isEmpty);
  });

  test('ClientToolExecuting appends an executing client-side entry', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );

    expect(ext.state, [
      const ToolCallEntry(
        toolCallId: 'tc-1',
        toolName: 'lookup',
        status: ToolCallStatus.executing,
        isClientSide: true,
      ),
    ]);
  });

  test('ServerToolCallStarted appends an executing server-side entry', () {
    session.events.value = const ServerToolCallStarted(
      toolCallId: 'tc-2',
      toolName: 'search',
    );

    expect(ext.state, [
      const ToolCallEntry(
        toolCallId: 'tc-2',
        toolName: 'search',
        status: ToolCallStatus.executing,
        isClientSide: false,
      ),
    ]);
  });

  test('ClientToolCompleted propagates the event status (completed)', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );
    session.events.value = const ClientToolCompleted(
      toolCallId: 'tc-1',
      result: 'ok',
      status: ToolCallStatus.completed,
    );

    expect(ext.state.single.status, ToolCallStatus.completed);
  });

  test('ClientToolCompleted propagates the event status (failed)', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );
    session.events.value = const ClientToolCompleted(
      toolCallId: 'tc-1',
      result: 'boom',
      status: ToolCallStatus.failed,
    );

    expect(ext.state.single.status, ToolCallStatus.failed);
  });

  test('ServerToolCallCompleted marks the matching entry completed', () {
    session.events.value = const ServerToolCallStarted(
      toolCallId: 'tc-2',
      toolName: 'search',
    );
    session.events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-2',
      result: 'done',
    );

    expect(ext.state.single.status, ToolCallStatus.completed);
  });

  test('re-entry of the same toolCallId updates in place', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );
    // A second ClientToolExecuting for the same call must not append a
    // duplicate; `_upsert` should mutate the existing entry while
    // preserving `toolName` and `side`.
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );

    expect(ext.state.length, 1);
    expect(ext.state.single.toolName, 'lookup');
    expect(ext.state.single.isClientSide, isTrue);
  });

  test('completion for unknown toolCallId is a no-op', () {
    session.events.value = const ServerToolCallCompleted(
      toolCallId: 'unknown',
      result: 'done',
    );

    expect(ext.state, isEmpty);
  });

  test('unrelated ExecutionEvent variants leave state unchanged', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'tc-1',
      toolName: 'lookup',
    );
    final before = ext.state;

    session.events.value = const ThinkingStarted();
    session.events.value = const ThinkingContent(delta: 'hmm');

    expect(identical(ext.state, before), isTrue);
  });

  test('preserves order across distinct tool calls', () {
    session.events.value = const ClientToolExecuting(
      toolCallId: 'a',
      toolName: 'first',
    );
    session.events.value = const ServerToolCallStarted(
      toolCallId: 'b',
      toolName: 'second',
    );
    session.events.value = const ClientToolExecuting(
      toolCallId: 'c',
      toolName: 'third',
    );

    expect(
      ext.state.map((e) => e.toolCallId).toList(),
      ['a', 'b', 'c'],
    );
  });

  test('onDispose stops applying further events', () {
    ext.onDispose();

    // If the subscription weren't torn down, the next event would fire
    // `_onEvent`, which reads the now-disposed `state` and throws an
    // assertion. Completing normally confirms the unsubscribe happened.
    expect(
      () => session.events.value = const ClientToolExecuting(
        toolCallId: 'tc-1',
        toolName: 'lookup',
      ),
      returnsNormally,
    );
  });

  test('onDispose is idempotent', () {
    ext.onDispose();
    expect(ext.onDispose, returnsNormally);
  });

  test('ToolCallEntry.copyWith preserves identity fields', () {
    const entry = ToolCallEntry(
      toolCallId: 'tc-1',
      toolName: 'lookup',
      status: ToolCallStatus.executing,
      isClientSide: true,
    );

    final completed = entry.copyWith(status: ToolCallStatus.completed);

    expect(completed.toolCallId, entry.toolCallId);
    expect(completed.toolName, entry.toolName);
    expect(completed.isClientSide, entry.isClientSide);
  });
}
