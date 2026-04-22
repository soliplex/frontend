import 'package:meta/meta.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart' show ToolCallStatus;

/// A tool call's current status during a session.
@immutable
class ToolCallEntry {
  const ToolCallEntry({
    required this.toolCallId,
    required this.toolName,
    required this.status,
    required this.isClientSide,
  });

  final String toolCallId;
  final String toolName;
  final ToolCallStatus status;

  /// True for client-side tool calls (executed locally), false for server-side.
  final bool isClientSide;

  ToolCallEntry copyWith({ToolCallStatus? status}) => ToolCallEntry(
        toolCallId: toolCallId,
        toolName: toolName,
        status: status ?? this.status,
        isClientSide: isClientSide,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallEntry &&
          toolCallId == other.toolCallId &&
          toolName == other.toolName &&
          status == other.status &&
          isClientSide == other.isClientSide;

  @override
  int get hashCode => Object.hash(toolCallId, toolName, status, isClientSide);
}

/// A [SessionExtension] that tracks tool call statuses reactively.
///
/// Subscribes to [AgentSession.lastExecutionEvent] in [onAttach] and maintains
/// an ordered list of [ToolCallEntry] values. Each entry records the call's
/// name, ID, whether it is client-side or server-side, and current status
/// (executing / completed / failed).
///
/// Resets to an empty list at the start of each new run via [RunCompleted]
/// and [RunFailed] terminal events clearing on the next session attach.
class ToolCallsExtension extends SessionExtension
    with StatefulSessionExtension<List<ToolCallEntry>> {
  ToolCallsExtension() {
    setInitialState(const []);
  }

  void Function()? _unsub;

  @override
  String get namespace => 'tool_calls';

  @override
  int get priority => 5;

  @override
  List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {
    _unsub = session.lastExecutionEvent.subscribe(_onEvent);
  }

  @override
  void onDispose() {
    _unsub?.call();
    _unsub = null;
    super.onDispose();
  }

  void _onEvent(ExecutionEvent? event) {
    if (event == null) return;
    final next = _reduce(state, event);
    if (!identical(next, state)) state = next;
  }

  static List<ToolCallEntry> _reduce(
    List<ToolCallEntry> entries,
    ExecutionEvent event,
  ) =>
      switch (event) {
        ClientToolExecuting(:final toolCallId, :final toolName) => _upsert(
            entries,
            toolCallId,
            toolName,
            ToolCallStatus.executing,
            isClientSide: true,
          ),
        ClientToolCompleted(:final toolCallId, :final status) =>
          _updateStatus(entries, toolCallId, status),
        ServerToolCallStarted(:final toolCallId, :final toolName) => _upsert(
            entries,
            toolCallId,
            toolName,
            ToolCallStatus.executing,
            isClientSide: false,
          ),
        ServerToolCallCompleted(:final toolCallId) =>
          _updateStatus(entries, toolCallId, ToolCallStatus.completed),
        _ => entries,
      };

  static List<ToolCallEntry> _upsert(
    List<ToolCallEntry> entries,
    String toolCallId,
    String toolName,
    ToolCallStatus status, {
    required bool isClientSide,
  }) {
    final idx = entries.indexWhere((e) => e.toolCallId == toolCallId);
    if (idx >= 0) {
      return [
        ...entries.sublist(0, idx),
        entries[idx].copyWith(status: status),
        ...entries.sublist(idx + 1),
      ];
    }
    return [
      ...entries,
      ToolCallEntry(
        toolCallId: toolCallId,
        toolName: toolName,
        status: status,
        isClientSide: isClientSide,
      ),
    ];
  }

  static List<ToolCallEntry> _updateStatus(
    List<ToolCallEntry> entries,
    String toolCallId,
    ToolCallStatus status,
  ) {
    final idx = entries.indexWhere((e) => e.toolCallId == toolCallId);
    if (idx < 0) return entries;
    return [
      ...entries.sublist(0, idx),
      entries[idx].copyWith(status: status),
      ...entries.sublist(idx + 1),
    ];
  }
}
