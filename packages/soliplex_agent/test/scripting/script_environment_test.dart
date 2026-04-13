import 'package:signals_core/signals_core.dart' show signal;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _TestScriptEnvironment implements ScriptEnvironment {
  _TestScriptEnvironment({this.toolList = const []});

  final List<ClientTool> toolList;
  int disposeCount = 0;

  @override
  List<ClientTool> get tools => toolList;

  @override
  ReadonlySignal<ScriptingState> get scriptingState =>
      signal(ScriptingState.idle).readonly();

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void dispose() => disposeCount++;
}

Future<ScriptEnvironment> _createTestEnvironment() async =>
    _TestScriptEnvironment();

void main() {
  group('ScriptEnvironment', () {
    test('tools returns provided tools', () {
      final tool = ClientTool(
        definition: const Tool(
          name: 'execute_python',
          description: 'Run Python',
        ),
        executor: (_, __) async => 'ok',
      );
      final env = _TestScriptEnvironment(toolList: [tool]);

      expect(env.tools, hasLength(1));
      expect(env.tools.first.definition.name, equals('execute_python'));
    });

    test('dispose is idempotent', () {
      final env = _TestScriptEnvironment()
        ..dispose()
        ..dispose();

      expect(env.disposeCount, equals(2));
    });

    test('empty tools list is valid', () {
      final env = _TestScriptEnvironment();

      expect(env.tools, isEmpty);
    });
  });

  group('ScriptEnvironmentFactory', () {
    test('factory typedef creates environments', () async {
      final env = await _createTestEnvironment();

      expect(env, isA<ScriptEnvironment>());
    });

    test('each factory call creates a fresh instance', () async {
      final env1 = await _createTestEnvironment();
      final env2 = await _createTestEnvironment();

      expect(identical(env1, env2), isFalse);
    });
  });
}
