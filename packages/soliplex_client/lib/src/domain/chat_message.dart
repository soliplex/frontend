import 'package:meta/meta.dart';

/// User type for messages.
enum ChatUser {
  /// Human user.
  user,

  /// AI assistant.
  assistant,

  /// System-generated message.
  system,
}

/// A chat message in a conversation.
@immutable
sealed class ChatMessage {
  /// Creates a chat message with the given properties.
  const ChatMessage({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  /// Unique identifier for this message.
  final String id;

  /// The user who sent this message.
  final ChatUser user;

  /// When this message was created.
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}

/// Reason a run reached a terminal state without producing assistant text.
///
/// Set on a `TextMessage` (with empty `text`) synthesized when a run finishes
/// with buffered thinking but no `TextMessageStart`/`Content`/`End` for an
/// assistant reply.
enum TerminalReason {
  /// Run completed normally (`RunFinishedEvent`).
  finished,

  /// Run failed (`RunErrorEvent`).
  failed,

  /// Run was cancelled (`cancelRun`).
  cancelled,
}

/// A text message.
@immutable
class TextMessage extends ChatMessage {
  /// Creates a text message with all properties.
  const TextMessage({
    required super.id,
    required super.user,
    required super.createdAt,
    required this.text,
    this.isStreaming = false,
    this.thinkingText = '',
    this.terminalReason,
  });

  /// Creates a text message with the given ID and auto-generated timestamp.
  factory TextMessage.create({
    required String id,
    required ChatUser user,
    required String text,
    bool isStreaming = false,
    String thinkingText = '',
    TerminalReason? terminalReason,
  }) {
    return TextMessage(
      id: id,
      user: user,
      text: text,
      isStreaming: isStreaming,
      thinkingText: thinkingText,
      terminalReason: terminalReason,
      createdAt: DateTime.now(),
    );
  }

  /// The message text content.
  final String text;

  /// Whether this message is currently streaming.
  final bool isStreaming;

  /// The thinking/reasoning text if available.
  final String thinkingText;

  /// Non-null when this message was synthesized for a run that terminated
  /// without an assistant reply. Carries enough state for the tile to
  /// render the appropriate "Run finished/failed/cancelled without a
  /// response" copy.
  final TerminalReason? terminalReason;

  /// Whether this message has thinking text.
  bool get hasThinkingText => thinkingText.isNotEmpty;

  /// Creates a copy with modified properties.
  TextMessage copyWith({
    String? id,
    ChatUser? user,
    DateTime? createdAt,
    String? text,
    bool? isStreaming,
    String? thinkingText,
    TerminalReason? terminalReason,
  }) {
    return TextMessage(
      id: id ?? this.id,
      user: user ?? this.user,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      thinkingText: thinkingText ?? this.thinkingText,
      terminalReason: terminalReason ?? this.terminalReason,
    );
  }

  @override
  String toString() => 'TextMessage(id: $id, user: $user)';
}

/// An error message.
@immutable
class ErrorMessage extends ChatMessage {
  /// Creates an error message with all properties.
  const ErrorMessage({
    required super.id,
    required super.createdAt,
    required this.errorText,
  }) : super(user: ChatUser.system);

  /// Creates an error message with the given ID and auto-generated timestamp.
  factory ErrorMessage.create({required String id, required String message}) {
    return ErrorMessage(id: id, errorText: message, createdAt: DateTime.now());
  }

  /// The error message text.
  final String errorText;

  @override
  String toString() => 'ErrorMessage(id: $id, error: $errorText)';
}

/// A tool call message.
@immutable
class ToolCallMessage extends ChatMessage {
  /// Creates a tool call message with all properties.
  const ToolCallMessage({
    required super.id,
    required super.createdAt,
    required this.toolCalls,
  }) : super(user: ChatUser.assistant);

  /// Creates a tool call message with the given ID and auto-generated
  /// timestamp.
  factory ToolCallMessage.create({
    required String id,
    required List<ToolCallInfo> toolCalls,
  }) {
    return ToolCallMessage(
      id: id,
      toolCalls: toolCalls,
      createdAt: DateTime.now(),
    );
  }

  /// Creates a [ToolCallMessage] from a list of executed tool calls.
  ///
  /// Used after client-side tool execution to append results to the
  /// conversation before starting a continuation run. The [toolCalls]
  /// should have `status: completed` or `status: failed` with results
  /// populated.
  factory ToolCallMessage.fromExecuted({
    required String id,
    required List<ToolCallInfo> toolCalls,
  }) {
    assert(
      toolCalls.every(
        (tc) =>
            tc.status == ToolCallStatus.completed ||
            tc.status == ToolCallStatus.failed,
      ),
      'All tool calls must have terminal status (completed or failed)',
    );
    return ToolCallMessage(
      id: id,
      toolCalls: toolCalls,
      createdAt: DateTime.now(),
    );
  }

  /// List of tool calls in this message.
  final List<ToolCallInfo> toolCalls;

  @override
  String toString() => 'ToolCallMessage(id: $id, calls: ${toolCalls.length})';
}

/// A generated UI message.
@immutable
class GenUiMessage extends ChatMessage {
  /// Creates a genUI message with all properties.
  const GenUiMessage({
    required super.id,
    required super.createdAt,
    required this.widgetName,
    required this.data,
  }) : super(user: ChatUser.assistant);

  /// Creates a genUI message with the given ID and auto-generated timestamp.
  factory GenUiMessage.create({
    required String id,
    required String widgetName,
    required Map<String, dynamic> data,
  }) {
    return GenUiMessage(
      id: id,
      widgetName: widgetName,
      data: data,
      createdAt: DateTime.now(),
    );
  }

  /// Name of the widget to render.
  final String widgetName;

  /// Data for the widget.
  final Map<String, dynamic> data;

  @override
  String toString() => 'GenUiMessage(id: $id, widget: $widgetName)';
}

/// A loading indicator message.
@immutable
class LoadingMessage extends ChatMessage {
  /// Creates a loading message with all properties.
  const LoadingMessage({required super.id, required super.createdAt})
      : super(user: ChatUser.assistant);

  /// Creates a loading message with the given ID and auto-generated timestamp.
  factory LoadingMessage.create({required String id}) {
    return LoadingMessage(id: id, createdAt: DateTime.now());
  }

  @override
  String toString() => 'LoadingMessage(id: $id)';
}

/// Where a dropped event was caught.
enum DropSource {
  /// `decodeEventSafely` produced `DecodeFailed` — either malformed JSON or
  /// a `type` field the decoder doesn't recognize.
  decode,

  /// The per-event-loop wrapper caught a throw from `processEvent` itself
  /// or one of its downstream side effects (e.g., citation extraction).
  eventProcessing,

  /// Historical replay bridging or `ExecutionTracker._onEvent` threw on a
  /// per-event basis.
  activityProcessing,

  /// Catch-all for future drop sites.
  other,
}

/// An event the client received but couldn't decode or process, surfaced as
/// a tile in the timeline so the user sees something happened and devs can
/// inspect the raw payload.
///
/// Synthesized by the data-layer wrappers in Phase 3
/// (`decodeEventSafely`, the per-event-loop wrapper, and the
/// `historical_replay` / `ExecutionTracker` boundaries). Never sent over
/// the wire.
@immutable
class DroppedEventMessage extends ChatMessage {
  /// Creates a dropped-event message with all properties.
  const DroppedEventMessage({
    required super.id,
    required super.createdAt,
    required this.source,
    required this.reason,
    this.runId,
    this.rawPayload,
  }) : super(user: ChatUser.system);

  /// Creates a dropped-event message with the given id and auto-generated
  /// timestamp.
  factory DroppedEventMessage.create({
    required String id,
    required DropSource source,
    required String reason,
    String? runId,
    Map<String, dynamic>? rawPayload,
  }) {
    return DroppedEventMessage(
      id: id,
      source: source,
      reason: reason,
      runId: runId,
      rawPayload: rawPayload,
      createdAt: DateTime.now(),
    );
  }

  /// Run the drop happened inside, when known. Null for non-run-scoped
  /// drops (e.g., decode failures that arrive before any run is in flight).
  final String? runId;

  /// Where the drop was caught.
  final DropSource source;

  /// Short human-readable reason. Shown as the collapsed-state subtitle.
  final String reason;

  /// Original payload for inspection. Null when serialization itself
  /// failed; the tile renders "(payload unavailable)" in that case.
  final Map<String, dynamic>? rawPayload;

  @override
  String toString() =>
      'DroppedEventMessage(id: $id, source: $source, reason: $reason)';
}

/// Status of a tool call.
enum ToolCallStatus {
  /// Tool call is still receiving argument chunks via ToolCallArgs deltas.
  streaming,

  /// Tool call arguments are complete, ready to execute.
  pending,

  /// Tool call is currently executing.
  executing,

  /// Tool call completed successfully.
  completed,

  /// Tool call failed.
  failed,
}

/// Information about a tool call.
@immutable
class ToolCallInfo {
  /// Creates tool call info with the given properties.
  const ToolCallInfo({
    required this.id,
    required this.name,
    this.arguments = '',
    this.status = ToolCallStatus.pending,
    this.result = '',
  });

  /// Unique identifier for this tool call.
  final String id;

  /// Name of the tool being called.
  final String name;

  /// JSON-encoded arguments for the tool.
  final String arguments;

  /// Current status of the tool call.
  final ToolCallStatus status;

  /// Result from the tool execution.
  final String result;

  /// Whether this tool call has arguments.
  bool get hasArguments => arguments.isNotEmpty;

  /// Whether this tool call has a result.
  bool get hasResult => result.isNotEmpty;

  /// Creates a copy with modified properties.
  ToolCallInfo copyWith({
    String? id,
    String? name,
    String? arguments,
    ToolCallStatus? status,
    String? result,
  }) {
    return ToolCallInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      status: status ?? this.status,
      result: result ?? this.result,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ToolCallInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ToolCallInfo(id: $id, name: $name, status: $status)';
}
