import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('ExecutionEvent', () {
    group('construction and equality', () {
      test('TextDelta equality', () {
        const a = TextDelta(delta: 'hello');
        const b = TextDelta(delta: 'hello');
        const c = TextDelta(delta: 'world');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('ThinkingStarted equality', () {
        const a = ThinkingStarted();
        const b = ThinkingStarted();

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('ThinkingContent equality', () {
        const a = ThinkingContent(delta: 'hmm');
        const b = ThinkingContent(delta: 'hmm');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('ServerToolCallStarted equality', () {
        const a = ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1');
        const b = ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1');
        const c = ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-2');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('ServerToolCallCompleted equality', () {
        const a = ServerToolCallCompleted(toolCallId: 'tc-1', result: 'ok');
        const b = ServerToolCallCompleted(toolCallId: 'tc-1', result: 'ok');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('ClientToolExecuting equality', () {
        const a = ClientToolExecuting(
          toolName: 'execute_python',
          toolCallId: 'tc-1',
        );
        const b = ClientToolExecuting(
          toolName: 'execute_python',
          toolCallId: 'tc-1',
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('ClientToolCompleted equality', () {
        const a = ClientToolCompleted(
          toolCallId: 'tc-1',
          result: '42',
          status: ToolCallStatus.completed,
        );
        const b = ClientToolCompleted(
          toolCallId: 'tc-1',
          result: '42',
          status: ToolCallStatus.completed,
        );
        const c = ClientToolCompleted(
          toolCallId: 'tc-1',
          result: '42',
          status: ToolCallStatus.failed,
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('RunCompleted equality', () {
        const a = RunCompleted();
        const b = RunCompleted();

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('RunFailed equality', () {
        const a = RunFailed(error: 'boom');
        const b = RunFailed(error: 'boom');
        const c = RunFailed(error: 'crash');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('RunCancelled equality', () {
        const a = RunCancelled();
        const b = RunCancelled();

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('StateUpdated equality', () {
        const a = StateUpdated(aguiState: {'key': 'value'});
        const b = StateUpdated(aguiState: {'key': 'value'});
        const c = StateUpdated(aguiState: {'key': 'other'});

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('StepProgress equality', () {
        const a = StepProgress(stepName: 'step1');
        const b = StepProgress(stepName: 'step1');
        const c = StepProgress(stepName: 'step2');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('CustomExecutionEvent equality', () {
        const a = CustomExecutionEvent(
          type: 'monty.started',
          payload: {'code': 'x=1'},
        );
        const b = CustomExecutionEvent(
          type: 'monty.started',
          payload: {'code': 'x=1'},
        );
        const c = CustomExecutionEvent(
          type: 'monty.started',
          payload: {'code': 'x=2'},
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('StateUpdated deep equality with nested maps', () {
        const a = StateUpdated(
          aguiState: {
            'nested': {'inner': 1},
            'list': [1, 2, 3],
          },
        );
        const b = StateUpdated(
          aguiState: {
            'nested': {'inner': 1},
            'list': [1, 2, 3],
          },
        );
        const c = StateUpdated(
          aguiState: {
            'nested': {'inner': 2},
            'list': [1, 2, 3],
          },
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('ActivitySnapshot equality', () {
        const a = ActivitySnapshot(
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
        );
        const b = ActivitySnapshot(
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
        );
        const c = ActivitySnapshot(
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask'},
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('CustomExecutionEvent deep equality with nested payload', () {
        const a = CustomExecutionEvent(
          type: 'test',
          payload: {
            'data': [1, 2],
            'meta': {'key': 'val'},
          },
        );
        const b = CustomExecutionEvent(
          type: 'test',
          payload: {
            'data': [1, 2],
            'meta': {'key': 'val'},
          },
        );
        const c = CustomExecutionEvent(
          type: 'test',
          payload: {
            'data': [1, 2],
            'meta': {'key': 'different'},
          },
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });
    });

    group('sealed class exhaustiveness', () {
      test('all variants are ExecutionEvent subtypes', () {
        final events = <ExecutionEvent>[
          const TextDelta(delta: ''),
          const ThinkingStarted(),
          const ThinkingContent(delta: ''),
          const ServerToolCallStarted(toolName: '', toolCallId: ''),
          const ServerToolCallCompleted(toolCallId: '', result: ''),
          const ClientToolExecuting(toolName: '', toolCallId: ''),
          const ClientToolCompleted(
            toolCallId: '',
            result: '',
            status: ToolCallStatus.completed,
          ),
          const RunCompleted(),
          const RunFailed(error: ''),
          const RunCancelled(),
          const StateUpdated(aguiState: {}),
          const StepProgress(stepName: ''),
          const CustomExecutionEvent(type: '', payload: {}),
          const ActivitySnapshot(activityType: '', content: {}),
        ];

        expect(events, hasLength(14));
        for (final event in events) {
          expect(event, isA<ExecutionEvent>());
        }
      });
    });

    group('ClientTool.simple with context-ignoring executor', () {
      test('works with (toolCall, _) signature', () async {
        final tool = ClientTool.simple(
          name: 'test',
          description: 'Test tool',
          executor: (toolCall, _) async => 'result',
        );

        expect(tool.definition.name, 'test');
        expect(tool.executor, isNotNull);
      });
    });
  });
}
