import 'package:soliplex_agent/src/host/agent_api.dart';
import 'package:soliplex_agent/src/models/agent_result.dart';

/// In-memory [AgentApi] for testing.
///
/// Records all calls and returns configurable responses.
/// Pattern matches `FakeHostApi`.
class FakeAgentApi implements AgentApi {
  /// Creates a fake agent API with optional canned responses.
  FakeAgentApi({
    this.spawnResult = 1,
    this.waitAllResult = const [],
    this.getResultResult = '',
    AgentResult? watchResult,
  }) : watchResult =
           watchResult ??
           const AgentSuccess(
             threadKey: (serverId: 'fake', roomId: 'fake', threadId: 'fake'),
             output: '',
             runId: 'fake-run',
           );

  /// Value returned by [spawnAgent]. Increments after each call.
  int spawnResult;

  /// Value returned by [waitAll].
  List<String> waitAllResult;

  /// Value returned by [getResult].
  String getResultResult;

  /// Value returned by [watchAgent]. Defaults to a success result.
  AgentResult watchResult;

  /// Recorded calls as `{methodName: [args]}`.
  final Map<String, List<Object?>> calls = {};

  /// Thread ID returned by [getThreadId].
  String threadIdResult = 'fake-thread-id';

  @override
  Future<int> spawnAgent(
    String roomId,
    String prompt, {
    String? threadId,
    Duration? timeout,
  }) async {
    calls['spawnAgent'] = [roomId, prompt, threadId, timeout];
    return spawnResult++;
  }

  @override
  String getThreadId(int handle) => threadIdResult;

  @override
  Future<List<String>> waitAll(List<int> handles, {Duration? timeout}) async {
    calls['waitAll'] = [handles, timeout];
    return waitAllResult;
  }

  @override
  Future<String> getResult(int handle, {Duration? timeout}) async {
    calls['getResult'] = [handle, timeout];
    return getResultResult;
  }

  @override
  Future<AgentResult> watchAgent(int handle, {Duration? timeout}) async {
    calls['watchAgent'] = [handle, timeout];
    return watchResult;
  }

  @override
  Future<void> cancelAgent(int handle) async {
    calls['cancelAgent'] = [handle];
  }

  /// Value returned by [agentStatus].
  String statusResult = 'running';

  @override
  String agentStatus(int handle) {
    calls['agentStatus'] = [handle];
    return statusResult;
  }
}
