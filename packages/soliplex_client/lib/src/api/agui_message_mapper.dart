import 'dart:convert';
import 'dart:typed_data';

import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.message_mapper');

/// Converts a list of [ChatMessage]s to AG-UI protocol [Message]s.
///
/// This mapper handles the conversion of internal chat message types to the
/// AG-UI protocol format required by the backend. The conversion rules are:
///
/// - [TextMessage] with [ChatUser.user] → [UserMessage]
/// - [TextMessage] with [ChatUser.assistant] → [AssistantMessage]
/// - [TextMessage] with [ChatUser.system] → [SystemMessage]
/// - [ToolCallMessage] → [AssistantMessage] with toolCalls, followed by
///   [ToolMessage]s for completed tool calls
/// - [GenUiMessage] → [AssistantMessage] with descriptive content
/// - [NoResponseTile] is skipped — round-tripping a synthesized empty
///   assistant tile would re-send it as a real assistant reply on the
///   next continuation run.
/// - [ErrorMessage], [LoadingMessage], [DroppedEventMessage] are skipped
///   (transient or frontend-only messages).
List<Message> convertToAgui(List<ChatMessage> chatMessages) {
  final result = <Message>[];

  for (final message in chatMessages) {
    switch (message) {
      case TextMessage():
        result.add(_convertTextMessage(message));

      case ToolCallMessage():
        result.addAll(_convertToolCallMessage(message));

      case GenUiMessage():
        result.add(_convertGenUiMessage(message));

      case ErrorMessage():
      case LoadingMessage():
      case DroppedEventMessage():
      case NoResponseTile():
        // Skip transient or frontend-only messages
        continue;
    }
  }

  return result;
}

Message _convertTextMessage(TextMessage message) {
  switch (message.user) {
    case ChatUser.user:
      final multimodalParts = _multimodalParts(message.parts);
      if (multimodalParts == null) {
        return UserMessage(id: message.id, content: message.text);
      }
      return UserMessage.multimodal(id: message.id, parts: multimodalParts);
    case ChatUser.assistant:
      return AssistantMessage(id: message.id, content: message.text);
    case ChatUser.system:
      return SystemMessage(id: message.id, content: message.text);
  }
}

/// Content parts for a multimodal `UserMessage`, or null when [parts] has
/// nothing the bare-string form cannot carry.
///
/// The multimodal arm of `content` is only worth using when a part isn't text;
/// a text-only list buys nothing the bare string does not already give us. An
/// *empty* array is worse than useless: `pydantic_ai`'s AG-UI adapter builds
/// the user's prompt only when the decoded content is non-empty, so an empty
/// array discards the turn with no error anywhere. Empty text runs are dropped
/// for the same reason in miniature — the OpenAI paths forward them verbatim
/// as empty text blocks instead of skipping them.
///
/// A [MissingAttachmentPart] is skipped: its content is exactly what this
/// client does not have, so there is nothing to send. The whole conversation
/// is re-sent on every run, so a message rebuilt from history goes back to the
/// model without the attachment it originally carried — unavoidable, and the
/// reason the bubble shows the user that it happened.
List<InputContent>? _multimodalParts(List<MessagePart>? parts) {
  if (parts == null) return null;

  final content = <InputContent>[];
  var hasSendablePart = false;
  for (final part in parts) {
    switch (part) {
      case TextPart(:final text):
        if (text.isEmpty) continue;
      case ImagePart():
        hasSendablePart = true;
      case MissingAttachmentPart():
        continue;
    }
    content.add(_convertMessagePart(part));
  }

  return hasSendablePart ? content : null;
}

/// The wire form of [part].
///
/// [MissingAttachmentPart] never reaches here — [_multimodalParts] drops it
/// before the call, because it has no wire form to produce.
InputContent _convertMessagePart(MessagePart part) {
  switch (part) {
    case TextPart():
      return TextInputContent(part.text);
    case ImagePart():
      return ImageInputContent(
        source: DataSource(
          value: base64Encode(part.bytes),
          mimeType: part.mimeType,
        ),
      );
    case MissingAttachmentPart():
      throw ArgumentError.value(
        part,
        'part',
        'has no wire form and must be dropped before conversion',
      );
  }
}

/// Reads a user message's wire `content` back into the domain — the inbound
/// counterpart to [_multimodalParts] and the bare-string arm of
/// [_convertTextMessage].
///
/// AG-UI gives `UserMessage.content` as either a bare string or an ordered list
/// of typed parts. `text` is the message's text either way: the bare string, or
/// every text part concatenated in order.
///
/// `parts` is non-null **only** when the content is an ordered list carrying at
/// least one attachment, because that is the only case where the parts say more
/// than `text` alone. It is null for a bare string and for a list of text
/// alone, which the bare-string form already carries — mirroring
/// [_multimodalParts] on the way out.
///
/// **One element costs no more than itself.** Every element is decoded on its
/// own, so a part this version cannot read leaves its siblings — text and
/// images alike — intact. Content the domain cannot hold becomes a
/// [MissingAttachmentPart] in the slot it occupied: a URL image source, audio,
/// video, a document, binary content, or bytes that will not decode. The
/// message keeps its shape and reports the gap, rather than dropping the
/// attachments silently and reading as though it never had any.
///
/// Content hydrates empty only when it holds no text to recover: absent, an
/// empty list, or a shape that is neither a string nor a list.
///
/// Never throws. A throw escaping here would abort a whole thread's history
/// load rather than one message, so the body is wrapped as a last resort.
///
/// [logContext] names the message being read — every warning below reports
/// content the user will not get back, and a log that cannot say which message
/// lost it cannot answer the question it exists to answer.
///
/// Public only so `SoliplexApi` can call it from another file in this package;
/// it is hidden at the barrel and is not part of the supported surface.
@internal
({List<MessagePart>? parts, String text}) readUserMessageContent(
  Object? content, {
  required String logContext,
}) {
  try {
    return _readContentParts(content, logContext);
  } on Object catch (error, stackTrace) {
    // Every failure below is handled where it happens, so reaching here means a
    // dependency started throwing where it did not before — our fault to fix,
    // not data to degrade. Logged at error for that reason, and still degraded
    // so one message cannot cost the thread.
    _logger.error(
      'Reading the content of $logContext threw; hydrating the message empty.',
      error: error,
      stackTrace: stackTrace,
    );
    return (parts: null, text: '');
  }
}

({List<MessagePart>? parts, String text}) _readContentParts(
  Object? content,
  String logContext,
) {
  if (content is String) return (parts: null, text: content);
  if (content == null) {
    // A message persisted without content at all. Distinguished from the drift
    // below because it is the one shape that says nothing went wrong.
    return (parts: null, text: '');
  }
  if (content is! List) {
    _logger.warning(
      'The content of $logContext is ${content.runtimeType}, not a string or a '
      'list of parts; hydrating the message empty.',
    );
    return (parts: null, text: '');
  }
  if (content.isEmpty) {
    // The shape `_multimodalParts` refuses to send: pydantic_ai's AG-UI adapter
    // builds the prompt only from non-empty content, so the model never saw
    // this turn. Only observable here, on the way back in.
    _logger.warning(
      'The content of $logContext is an empty list; the model was given no '
      'prompt for that turn.',
    );
    return (parts: null, text: '');
  }

  final parts = <MessagePart>[];

  for (var i = 0; i < content.length; i++) {
    final decoded = _decodeContentPart(content[i], i, logContext);
    if (decoded == null) {
      // Undecodable as a part at all, so its kind is unknown too — but it
      // occupied a slot, and saying so beats leaving a hole in the message.
      parts.add(
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.undecodable,
        ),
      );
      continue;
    }
    switch (decoded) {
      case TextInputContent(:final text):
        parts.add(TextPart(text));
      case ImageInputContent(:final source):
        parts.add(_readImageSource(source, i, logContext));
      // Explicit arms rather than a default: a new content type upstream should
      // be a compile error here, not a silently dropped attachment. The media
      // kinds are grouped because they carry their type the same way; binary
      // declares one directly.
      case AudioInputContent(:final source) ||
            VideoInputContent(:final source) ||
            DocumentInputContent(:final source):
        parts.add(
          _unsupportedAttachment(
            decoded.type,
            _sourceMimeType(source),
            i,
            logContext,
          ),
        );
      case BinaryInputContent(:final mimeType):
        parts.add(
          _unsupportedAttachment(decoded.type, mimeType, i, logContext),
        );
    }
  }

  final text = parts.plainText;
  // A list of text alone says no more than the bare string does, so it takes
  // the plain path — matching what `_multimodalParts` would send.
  if (!parts.hasAttachment) return (parts: null, text: text);
  return (parts: parts, text: text);
}

/// The MIME type [source] declared, or null when it named none. Required on a
/// [DataSource] and optional on a [UrlSource], so only the latter can be null.
String? _sourceMimeType(InputContentSource source) => switch (source) {
      DataSource(:final mimeType) => mimeType,
      UrlSource(:final mimeType) => mimeType,
    };

/// The placeholder for a part that decoded cleanly but has no domain
/// equivalent, logged as it is built.
///
/// [mimeType] is what the sender declared. It is the only thing the placeholder
/// can say about what is missing — the glyph is the same for every kind — so it
/// is carried through wherever the payload names one.
MissingAttachmentPart _unsupportedAttachment(
  String type,
  String? mimeType,
  int index,
  String logContext,
) {
  _logger.warning(
    'Content[$index] of $logContext is $type content, which has no domain '
    'part; showing it as a missing attachment.',
  );
  return MissingAttachmentPart(
    reason: MissingAttachmentReason.unsupportedType,
    mimeType: mimeType,
  );
}

/// The AG-UI content part at [index] of a message's content list, or null when
/// it cannot be decoded.
///
/// Decoded one element at a time rather than through
/// `UserMessageContent.fromJson`, which is all-or-nothing: a single unknown
/// part type there discards the whole list, taking the message's text with it.
InputContent? _decodeContentPart(Object? raw, int index, String logContext) {
  if (raw is! Map<String, dynamic>) {
    _logger.warning(
      'Content[$index] of $logContext is ${raw.runtimeType}, not an object; '
      'showing it as a missing attachment.',
    );
    return null;
  }
  try {
    return InputContent.fromJson(raw);
  } on AGUIValidationError catch (error) {
    // Shape drift in someone else's data — an unknown part type, or a known one
    // missing a required field.
    _logger.warning(
      'Content[$index] of $logContext is not a part this protocol version '
      'describes; showing it as a missing attachment.',
      error: error,
    );
    return null;
  } on Object catch (error, stackTrace) {
    _logger.error(
      'Content[$index] of $logContext threw unexpectedly while decoding; '
      'showing it as a missing attachment.',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// The [ImagePart] for the image content [source] at [index], or a
/// [MissingAttachmentPart] when the source is one the domain cannot hold.
MessagePart _readImageSource(
  InputContentSource source,
  int index,
  String logContext,
) {
  switch (source) {
    case DataSource(:final value, :final mimeType):
      final Uint8List bytes;
      try {
        bytes = base64Decode(value);
      } on FormatException catch (error) {
        _logger.warning(
          'Content[$index] of $logContext has undecodable base64; showing it '
          'as a missing attachment.',
          error: error,
        );
        return MissingAttachmentPart(
          reason: MissingAttachmentReason.undecodable,
          mimeType: mimeType,
        );
      }
      if (bytes.isEmpty) {
        // Valid base64 for zero bytes. No decoder can render it, so an
        // ImagePart here would only fail again at paint time.
        _logger.warning(
          'Content[$index] of $logContext carries an empty image payload; '
          'showing it as a missing attachment.',
        );
        return MissingAttachmentPart(
          reason: MissingAttachmentReason.undecodable,
          mimeType: mimeType,
        );
      }
      return ImagePart(bytes: bytes, mimeType: mimeType);
    case UrlSource(:final mimeType):
      // We only ever send DataSource, so a URL here came from another client.
      // ImagePart holds bytes and cannot represent one, and fetching it during
      // hydration is out of scope.
      _logger.warning(
        'Content[$index] of $logContext is an image given as a URL, which has '
        'no domain part; showing it as a missing attachment.',
      );
      return MissingAttachmentPart(
        reason: MissingAttachmentReason.remoteSource,
        mimeType: mimeType,
      );
  }
}

List<Message> _convertToolCallMessage(ToolCallMessage message) {
  final toolCalls = message.toolCalls
      .map(
        (tc) => ToolCall(
          id: tc.id,
          function: FunctionCall(
            name: tc.name,
            arguments: tc.arguments.isEmpty ? '{}' : tc.arguments,
          ),
        ),
      )
      .toList();

  final result = <Message>[
    AssistantMessage(id: message.id, toolCalls: toolCalls),
  ];

  // Add ToolMessage for each completed or failed tool call.
  // Failed tool calls send their error to the model so it can respond.
  for (final tc in message.toolCalls) {
    if (tc.status == ToolCallStatus.completed ||
        tc.status == ToolCallStatus.failed) {
      result.add(
        ToolMessage(
          id: 'tool_result_${tc.id}',
          toolCallId: tc.id,
          content: tc.result,
        ),
      );
    }
  }

  return result;
}

Message _convertGenUiMessage(GenUiMessage message) {
  final dataJson = jsonEncode(message.data);
  final content =
      'Displayed ${message.widgetName} component with data: $dataJson';

  return AssistantMessage(id: message.id, content: content);
}
