import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One element of a user message's ordered content.
///
/// Carried by [TextMessage.parts] on a user message built from an ordered
/// payload. One list serves both the optimistic echo and the AG-UI wire
/// mapping, so what the sender sees and what the model receives cannot drift.
@immutable
sealed class MessagePart {
  /// Creates a message part.
  const MessagePart();
}

/// A run of text within a message's ordered content.
@immutable
final class TextPart extends MessagePart {
  /// Creates a text part carrying [text].
  const TextPart(this.text);

  /// The text payload.
  final String text;
}

/// A part that occupies an attachment's place in a message, whether or not its
/// content can still be produced.
///
/// Carries [number] because an attachment is the only kind of part a reader
/// refers to by name — "what does the sign in image 7 say" — and text is not.
@immutable
sealed class AttachmentPart extends MessagePart {
  /// Creates an attachment part numbered [number].
  const AttachmentPart({required this.number});

  /// What this attachment is called, for as long as the thread lasts.
  ///
  /// Assigned once, when the message carrying it is first sent, and carried
  /// from then on rather than derived — a number worked out afresh from a
  /// message's present shape changes when that shape does, and an answer given
  /// three turns ago still names the number it was told.
  ///
  /// Null for an attachment that was never numbered: one from a payload that
  /// carries no number, or one written by another client. It is shown without a
  /// number and sent without a name, because it has none the model would
  /// recognise.
  final int? number;

  /// This attachment under a different name.
  ///
  /// Declared here so that every attachment can be named: a subtype that could
  /// not would be passed over by [MessagePartsText.numberedFrom] and reach the
  /// model unnamed. Requiring it makes that a compile error instead.
  AttachmentPart withNumber(int number);
}

/// An image within a message's ordered content.
@immutable
final class ImagePart extends AttachmentPart {
  /// Creates an image part from raw [bytes] of type [mimeType].
  const ImagePart({
    required this.bytes,
    required this.mimeType,
    super.number,
  });

  /// The encoded image file bytes — not decoded pixels.
  final Uint8List bytes;

  /// The MIME type of [bytes], e.g. `image/png`.
  final String mimeType;

  @override
  ImagePart withNumber(int number) =>
      ImagePart(bytes: bytes, mimeType: mimeType, number: number);
}

/// Why an attachment a message was sent with cannot be shown again.
enum MissingAttachmentReason {
  /// The payload could not be read — an element this protocol version cannot
  /// describe, invalid base64, or a valid encoding of nothing.
  undecodable,

  /// A kind of content this domain has no part for: audio, video, a document,
  /// or opaque binary.
  unsupportedType,

  /// Held somewhere else rather than sent inline, as a URL this client does
  /// not fetch.
  remoteSource,
}

/// An attachment that was part of a message but whose content cannot be
/// reconstructed, holding its place in the ordered content.
///
/// Kept as a part rather than dropped so a message reports what it was sent
/// with. Silently removing it would leave a bubble that reads as complete
/// while the model was given something else — the stronger false claim of the
/// two. [mimeType] is the type the sender declared, when the payload named one
/// at all.
@immutable
final class MissingAttachmentPart extends AttachmentPart {
  /// Creates a placeholder for an attachment that cannot be reconstructed.
  const MissingAttachmentPart({
    required this.reason,
    this.mimeType,
    super.number,
  });

  /// Why the attachment cannot be shown.
  final MissingAttachmentReason reason;

  /// The MIME type the sender declared, or null when the payload named none.
  final String? mimeType;

  @override
  MissingAttachmentPart withNumber(int number) =>
      MissingAttachmentPart(reason: reason, mimeType: mimeType, number: number);
}

/// What an ordered part list carries: its text, and whether it holds anything
/// beyond text.
extension MessagePartsText on List<MessagePart> {
  /// Every [TextPart]'s text, concatenated in order, with no separator.
  ///
  /// Lossy by nature: an image carries no text and is dropped, so anything
  /// that stores or displays this alone keeps the words and loses the images.
  String get plainText => whereType<TextPart>().map((part) => part.text).join();

  /// Whether any part carries something other than text — an image, or an
  /// attachment that could not be reconstructed.
  ///
  /// This is what makes an ordered list worth keeping: a list of text alone
  /// says no more than [plainText] does, and travels the wire as a bare
  /// string.
  bool get hasAttachment => any((part) => part is AttachmentPart);

  /// The highest number any attachment here has been given, or null when none
  /// carries one.
  int? get highestAttachmentNumber {
    int? highest;
    for (final part in whereType<AttachmentPart>()) {
      final number = part.number;
      if (number != null && (highest == null || number > highest)) {
        highest = number;
      }
    }
    return highest;
  }

  /// These parts with every unnamed attachment named, counting up from
  /// [firstNumber].
  ///
  /// Numbers are handed out here, once, and travel with the parts from then on.
  /// Anything already numbered keeps the number it has: it is what the model
  /// was told, and a reply may already refer to it.
  List<MessagePart> numberedFrom(int firstNumber) {
    var next = firstNumber;
    return [
      for (final part in this)
        if (part is AttachmentPart && part.number == null)
          part.withNumber(next++)
        else
          part,
    ];
  }
}

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
    this.thinkingText = '',
    this.parts,
  });

  /// Creates a text message with the given ID. [createdAt] is the
  /// backend-sourced time, or null when none is known yet (e.g. the live
  /// optimistic echo). The model never substitutes a client `now()`.
  factory TextMessage.create({
    required String id,
    required ChatUser user,
    required String text,
    DateTime? createdAt,
    String thinkingText = '',
  }) {
    return TextMessage(
      id: id,
      user: user,
      text: text,
      thinkingText: thinkingText,
      createdAt: createdAt,
    );
  }

  /// Creates a user message for an ordered [parts] payload, deriving [text]
  /// from the parts so a caller of this factory cannot let the two disagree.
  /// Holds an unmodifiable copy, so a caller that kept its own list cannot
  /// mutate it afterwards and leave [text] describing different content.
  ///
  /// Parts are honoured only for a user message, so the role is fixed.
  ///
  /// Throws [ArgumentError] when [parts] carries neither an attachment nor any
  /// text. Such a payload reaches the wire as empty content, which makes the
  /// backend discard the turn without reporting an error — a throw here is
  /// the only way the caller learns the message went nowhere.
  ///
  /// A [MissingAttachmentPart] satisfies the requirement even though it has no
  /// wire form: it is the whole reason a message rebuilt from history still has
  /// something to render. Such a message is still re-sent on the next run, and
  /// a parts list of placeholders alone contributes nothing — so it reaches the
  /// backend as empty content, and that turn is discarded there.
  factory TextMessage.fromParts({
    required String id,
    required List<MessagePart> parts,
    DateTime? createdAt,
  }) {
    if (parts.plainText.isEmpty && !parts.hasAttachment) {
      throw ArgumentError.value(
        parts,
        'parts',
        'must carry an attachment or some text',
      );
    }
    return TextMessage(
      id: id,
      user: ChatUser.user,
      text: parts.plainText,
      createdAt: createdAt,
      parts: List.unmodifiable(parts),
    );
  }

  /// The message text content.
  final String text;

  /// Ordered content parts, set on a user message built by
  /// [TextMessage.fromParts] and null on one built by [TextMessage.create].
  /// A list holding nothing but text still travels the wire as a bare string,
  /// so `parts != null` means "built from a payload", not "has an image" —
  /// test for an image with `parts?.whereType<ImagePart>().isNotEmpty`, and
  /// for any attachment with `hasAttachment`. Only honoured for user messages,
  /// ignored elsewhere.
  ///
  /// When set, [text] must hold the flattened text of these parts. The mapper
  /// falls back to [text] for any parts list it cannot send as multimodal, and
  /// the timeline and copy button read [text] directly, so a [text] that
  /// disagrees silently changes what the user copies or the model receives.
  final List<MessagePart>? parts;

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
    String? thinkingText,
  }) {
    return TextMessage(
      id: id ?? this.id,
      user: user ?? this.user,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      thinkingText: thinkingText ?? this.thinkingText,
      parts: parts,
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
  /// populated. Stamped with the client clock at creation, since a locally
  /// executed result has no backend time.
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
