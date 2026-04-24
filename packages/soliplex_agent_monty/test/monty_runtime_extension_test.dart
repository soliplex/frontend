import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart'
    show AgentSession, ToolCallInfo;
// ToolExecutionContext is not re-exported from soliplex_agent's public
// barrel; reach into src/ for the test fake.
import 'package:soliplex_agent/src/tools/tool_execution_context.dart'
    show ToolExecutionContext;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';
import 'package:test/test.dart';

class _FakeToolExecutionContext implements ToolExecutionContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('MontyRuntimeExtension', () {
    late MontyRuntimeExtension ext;

    setUp(() {
      ext = MontyRuntimeExtension(extensions: MontyExtensionSet.standard());
    });

    tearDown(() => ext.onDispose());

    test('namespace is "monty"', () {
      expect(ext.namespace, 'monty');
    });

    test('exposes one ClientTool named run_python_on_device', () {
      expect(ext.tools, hasLength(1));
      expect(ext.tools.single.definition.name, 'run_python_on_device');
    });

    test('tool description mentions on-device execution', () {
      final desc = ext.tools.single.definition.description;
      expect(desc, contains('on the user'));
      expect(desc, contains('device'));
      // No cross-reference to server-side tool names:
      expect(desc, isNot(contains('run_python ')));
    });

    test('tool parameter schema requires a string "code"', () {
      final params =
          ext.tools.single.definition.parameters as Map<String, Object?>;
      final props = params['properties']! as Map<String, Object?>;
      final codeProp = props['code']! as Map<String, Object?>;
      expect(codeProp['type'], 'string');
      expect(params['required'], contains('code'));
    });

    test('tool executor returns error JSON when not attached', () async {
      // No onAttach called; runtime is null.
      final result = await ext.tools.single.executor(
        const ToolCallInfo(
          id: 'tc-1',
          name: 'run_python_on_device',
          arguments: '{"code": "1 + 1"}',
        ),
        _FakeToolExecutionContext(),
      );
      final payload = jsonDecode(result) as Map<String, Object?>;
      expect(payload['error'], contains('not attached'));
    });

    test('initial state is empty map', () {
      expect(ext.state, <String, Object?>{});
    });
  });

  group('MontyRuntimeExtension — argument parsing', () {
    late MontyRuntimeExtension ext;

    setUp(() {
      ext = MontyRuntimeExtension(extensions: MontyExtensionSet.standard());
    });

    tearDown(() => ext.onDispose());

    test('missing code field returns error', () async {
      final result = await ext.tools.single.executor(
        const ToolCallInfo(
          id: 'tc-1',
          name: 'run_python_on_device',
          arguments: '{"other": "value"}',
        ),
        _FakeToolExecutionContext(),
      );
      final payload = jsonDecode(result) as Map<String, Object?>;
      expect(payload['error'], contains('"code"'));
    });

    test('non-string code field returns error', () async {
      final result = await ext.tools.single.executor(
        const ToolCallInfo(
          id: 'tc-1',
          name: 'run_python_on_device',
          arguments: '{"code": 123}',
        ),
        _FakeToolExecutionContext(),
      );
      final payload = jsonDecode(result) as Map<String, Object?>;
      expect(payload['error'], contains('must be a string'));
    });

    test('malformed JSON returns error', () async {
      final result = await ext.tools.single.executor(
        const ToolCallInfo(
          id: 'tc-1',
          name: 'run_python_on_device',
          arguments: 'not-json',
        ),
        _FakeToolExecutionContext(),
      );
      final payload = jsonDecode(result) as Map<String, Object?>;
      expect(payload['error'], contains('parse arguments'));
    });
  });

  group(
    'MontyRuntimeExtension — attached (native Monty runtime)',
    () {
      late MontyRuntimeExtension ext;

      setUp(() async {
        ext = MontyRuntimeExtension(extensions: MontyExtensionSet.standard());
        // onAttach constructs MontyRuntime; this touches the native
        // dart_monty backend and will fail if the native lib is not
        // available in the test environment.
        await ext.onAttach(_FakeAgentSession());
      });

      tearDown(() => ext.onDispose());

      test('runs trivial Python and captures print output', () async {
        final result = await ext.tools.single.executor(
          ToolCallInfo(
            id: 'tc-1',
            name: 'run_python_on_device',
            arguments: jsonEncode({'code': "print('hi')\n2 + 2"}),
          ),
          _FakeToolExecutionContext(),
        );
        final payload = jsonDecode(result) as Map<String, Object?>;
        // value should be 4; output should contain 'hi'.
        expect(payload['error'], isNull);
        expect(payload['output'], contains('hi'));
      });

      test('Python syntax error returns error payload', () async {
        final result = await ext.tools.single.executor(
          const ToolCallInfo(
            id: 'tc-1',
            name: 'run_python_on_device',
            arguments: '{"code": "def broken(:"}',
          ),
          _FakeToolExecutionContext(),
        );
        final payload = jsonDecode(result) as Map<String, Object?>;
        expect(payload['error'], isNotNull);
      });
    },
    tags: [
      'native',
    ],
  );
}

class _FakeAgentSession implements AgentSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
