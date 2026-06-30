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

  /// When this message was created. Backend-driven messages carry the backend's
  /// time: replayed or terminal text and run finished/errored use
  /// `event.timestamp` (falling back to the run's `created`), and a reply cut
  /// off by a cancel keeps its last received backend event time. Client-only
  /// artifacts carry the client clock at creation, since they have no backend
  /// counterpart — the user-cancelled tile (the cancel instant), the loading
  /// placeholder, the in-flight streaming tile, and locally executed tool
  /// results. Null when no authoritative time is known yet — e.g. the
  /// optimistic user echo before the run is persisted, which fills in from the
  /// run's `created` on replay.
  final DateTime? createdAt;

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
/// Carried by [NoResponseTile] when a run ends without a
/// `TextMessageStart`/`Content`/`End` for an assistant reply.
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
  });

  /// Creates a text message with the given ID. [createdAt] is the
  /// backend-sourced time, or null when none is known yet (e.g. the live
  /// optimistic echo). The model never substitutes a client `now()`.
  factory TextMessage.create({
    required String id,
    required ChatUser user,
    required String text,
    DateTime? createdAt,
    bool isStreaming = false,
    String thinkingText = '',
  }) {
    return TextMessage(
      id: id,
      user: user,
      text: text,
      isStreaming: isStreaming,
      thinkingText: thinkingText,
      createdAt: createdAt,
    );
  }

  /// The message text content.
  final String text;

  /// Whether this message is currently streaming.
  final bool isStreaming;

  /// The thinking/reasoning text if available.
  final String thinkingText;

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
  }) {
    return TextMessage(
      id: id ?? this.id,
      user: user ?? this.user,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      thinkingText: thinkingText ?? this.thinkingText,
    );
  }

  @override
  String toString() => 'TextMessage(id: $id, user: $user)';
}

/// Synthesized assistant tile shown when a run reached a terminal state
/// without producing a `TextMessageStart`/`Content`/`End` reply.
///
/// Carries the run's buffered thinking (if any) and the [reason] the run
/// ended so the UI can render the appropriate muted "Run
/// finished/failed/cancelled without a response" tile. Frontend-only —
/// never sent over the wire (filtered in `agui_message_mapper.dart`).
///
/// Construct via the named factories ([NoResponseTile.failed],
/// [NoResponseTile.cancelled], [NoResponseTile.finished]); the link between
/// `reason` and `errorDetail` is enforced at the type level.
@immutable
class NoResponseTile extends ChatMessage {
  /// Run failed (`RunErrorEvent`). [errorDetail] is the backend message so
  /// the tile renders "Run failed: <detail>" rather than the generic copy.
  factory NoResponseTile.failed({
    required String id,
    required String thinkingText,
    required String errorDetail,
    DateTime? createdAt,
  }) =>
      NoResponseTile._(
        id: id,
        createdAt: createdAt,
        thinkingText: thinkingText,
        reason: TerminalReason.failed,
        errorDetail: errorDetail,
      );

  /// Run was cancelled (`cancelRun`).
  factory NoResponseTile.cancelled({
    required String id,
    required String thinkingText,
    DateTime? createdAt,
  }) =>
      NoResponseTile._(
        id: id,
        createdAt: createdAt,
        thinkingText: thinkingText,
        reason: TerminalReason.cancelled,
        errorDetail: null,
      );

  /// Run completed normally (`RunFinishedEvent`).
  factory NoResponseTile.finished({
    required String id,
    required String thinkingText,
    DateTime? createdAt,
  }) =>
      NoResponseTile._(
        id: id,
        createdAt: createdAt,
        thinkingText: thinkingText,
        reason: TerminalReason.finished,
        errorDetail: null,
      );

  const NoResponseTile._({
    required super.id,
    required super.createdAt,
    required this.thinkingText,
    required this.reason,
    required this.errorDetail,
  }) : super(user: ChatUser.assistant);

  /// Buffered thinking captured before the run terminated. May be empty.
  final String thinkingText;

  /// The terminal disposition of the run.
  final TerminalReason reason;

  /// Backend error message for `TerminalReason.failed`. Always null for
  /// `finished` and `cancelled` — the named factories enforce this.
  final String? errorDetail;

  /// Whether this tile has thinking text to display.
  bool get hasThinkingText => thinkingText.isNotEmpty;

  @override
  String toString() => 'NoResponseTile(id: $id, reason: $reason)';
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

  /// Creates an error message with the given ID. [createdAt] is the
  /// backend-sourced time (the error event's timestamp or the run's
  /// `created`), or null when none is known yet.
  factory ErrorMessage.create({
    required String id,
    required String message,
    DateTime? createdAt,
  }) {
    return ErrorMessage(
      id: id,
      errorText: message,
      createdAt: createdAt,
    );
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

  /// Creates a tool call message with the given ID, stamped with the client
  /// clock at creation (created client-side; no backend time).
  factory ToolCallMessage.create({
    required String id,
    required List<ToolCallInfo> toolCalls,
  }) {
    return ToolCallMessage(
      id: id,
      toolCalls: toolCalls,
      createdAt: DateTime.timestamp(),
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
      createdAt: DateTime.timestamp(),
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

  /// Creates a genUI message with the given ID, stamped with the client clock
  /// at creation (created client-side; no backend time).
  factory GenUiMessage.create({
    required String id,
    required String widgetName,
    required Map<String, dynamic> data,
  }) {
    return GenUiMessage(
      id: id,
      widgetName: widgetName,
      data: data,
      createdAt: DateTime.timestamp(),
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

  /// Creates a loading message with the given ID, stamped with the client clock
  /// at creation (a transient client-side placeholder with no backend time).
  factory LoadingMessage.create({required String id}) {
    return LoadingMessage(id: id, createdAt: DateTime.timestamp());
  }

  @override
  String toString() => 'LoadingMessage(id: $id)';
}

/// Where a dropped event was caught.
enum DropSource {
  /// The decoder rejected the payload — malformed JSON, a non-object
  /// scalar, an unknown event type, or a schema mismatch on a known type.
  decode,

  /// The per-event-loop wrapper caught a throw from `processEvent` itself.
  eventProcessing,
}

/// An event the client received but couldn't decode or process, surfaced as
/// a tile in the timeline so the user sees something happened and devs can
/// inspect the raw payload.
///
/// Synthesized at two content-bearing boundaries: the decode boundary
/// (`decodeMapSafely` returns `DecodeFailed`) and the per-event-loop body
/// in `RunOrchestrator._onEvent` / `SoliplexApi._replayEventsToHistory`
/// (`processEvent` threw). Citation extraction, historical replay
/// bridging, and tracker projection log only without minting a tile —
/// failures there don't lose user-facing content. Never sent over the
/// wire (filtered in `agui_message_mapper.dart`).
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

  /// Creates a dropped-event message with the given id. [createdAt] is the
  /// run's `created` on replay, or null for a live drop (no authoritative
  /// time yet); the model never substitutes a client `now()`.
  factory DroppedEventMessage.create({
    required String id,
    required DropSource source,
    required String reason,
    String? runId,
    Object? rawPayload,
    DateTime? createdAt,
  }) {
    return DroppedEventMessage(
      id: id,
      source: source,
      reason: reason,
      runId: runId,
      rawPayload: rawPayload,
      createdAt: createdAt,
    );
  }

  /// Run the drop happened inside, when known. Null for non-run-scoped
  /// drops (e.g., decode failures that arrive before any run is in flight).
  final String? runId;

  /// Where the drop was caught.
  final DropSource source;

  /// Short human-readable reason. Shown as the collapsed-state subtitle.
  final String reason;

  /// Original payload for inspection. Shape mirrors `DecodeFailed.rawData`:
  /// `Map` for per-event decoder failures, `String` for top-level JSON
  /// parse failures, or any non-Map JSON value (list/scalar). Null when
  /// the surrounding boundary couldn't carry the payload at all; the
  /// tile renders "(payload unavailable)" in that case.
  final Object? rawPayload;

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
