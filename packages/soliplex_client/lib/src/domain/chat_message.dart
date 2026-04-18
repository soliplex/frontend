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

  /// Creates a text message with the given ID and auto-generated timestamp.
  factory TextMessage.create({
    required String id,
    required ChatUser user,
    required String text,
    bool isStreaming = false,
    String thinkingText = '',
  }) {
    return TextMessage(
      id: id,
      user: user,
      text: text,
      isStreaming: isStreaming,
      thinkingText: thinkingText,
      createdAt: DateTime.now(),
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
            tc.status == ToolCallStatus.failed ||
            tc.status == ToolCallStatus.denied,
      ),
      'All tool calls must have terminal status (completed, failed, or denied)',
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

/// A client-injected system info message.
///
/// Surfaces ephemeral notifications inline in the chat. Client-only — never
/// persisted to the server.
@immutable
class SystemInfoMessage extends ChatMessage {
  /// Creates a system info message with all properties.
  const SystemInfoMessage({
    required super.id,
    required super.createdAt,
    required this.text,
    this.format = 'markdown',
  }) : super(user: ChatUser.system);

  /// Creates a system info message with the given ID and auto-generated
  /// timestamp.
  factory SystemInfoMessage.create({
    required String id,
    required String text,
    String format = 'markdown',
  }) {
    return SystemInfoMessage(
      id: id,
      text: text,
      format: format,
      createdAt: DateTime.now(),
    );
  }

  /// The message text content.
  final String text;

  /// Content format hint: 'markdown' (default) or 'plain'.
  final String format;

  @override
  String toString() => 'SystemInfoMessage(id: $id)';
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

/// Status of a tool call.
enum ToolCallStatus {
  /// Tool call is still receiving argument chunks via ToolCallArgs deltas.
  streaming,

  /// Tool call arguments are complete, ready to execute.
  pending,

  /// Tool call is currently executing.
  executing,

  /// Tool call is awaiting human approval before executing.
  awaitingApproval,

  /// Tool call was denied by the user.
  denied,

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
