import 'package:soliplex_agent/soliplex_agent.dart';

/// Test double for [ToolExecutionContext].
///
/// All methods throw [UnimplementedError] by default. Override individual
/// methods in tests that exercise specific context interactions.
class FakeToolExecutionContext implements ToolExecutionContext {
  @override
  CancelToken get cancelToken => throw UnimplementedError();

  @override
  Future<AgentSession> spawnChild({required String prompt, String? roomId}) =>
      throw UnimplementedError();

  @override
  void emitEvent(ExecutionEvent event) => throw UnimplementedError();

  @override
  T? getExtension<T extends SessionExtension>() => throw UnimplementedError();

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> delegateTask({
    required String prompt,
    String? roomId,
    Duration? timeout,
  }) =>
      throw UnimplementedError();
}
