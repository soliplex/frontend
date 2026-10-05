import 'package:ag_ui/ag_ui.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A tool call whose start has arrived but not its end, and the assistant
/// message it joins when it ends.
typedef OpenToolCall = ({ToolCall call, String parentId});

/// The AG-UI messages a thread sends as its history, in the order the events
/// that made them arrived, with what building it carries from one event to
/// the next.
@immutable
class Transcript {
  /// Creates a transcript.
  const Transcript({
    this.messages = const [],
    this.openToolCalls = const {},
    this.endedToolCallIds = const {},
  });

  /// The messages to send.
  final List<Message> messages;

  /// Calls started and not yet ended, by id. A call joins its parent only
  /// when it ends, so one that never ends is never sent.
  final Map<String, OpenToolCall> openToolCalls;

  /// Ids of calls that ended, which are the calls a result may answer. A
  /// call starting under an id removes it until that call ends, so an
  /// earlier call's end never vouches for a later one that reused its id.
  final Set<String> endedToolCallIds;

  /// Returns a copy with [message] appended.
  Transcript withAppendedMessage(Message message) =>
      copyWith(messages: [...messages, message]);

  /// Creates a copy with the given fields replaced.
  Transcript copyWith({
    List<Message>? messages,
    Map<String, OpenToolCall>? openToolCalls,
    Set<String>? endedToolCallIds,
  }) =>
      Transcript(
        messages: messages ?? this.messages,
        openToolCalls: openToolCalls ?? this.openToolCalls,
        endedToolCallIds: endedToolCallIds ?? this.endedToolCallIds,
      );

  /// AG-UI messages have no value equality, so messages compare by identity:
  /// two transcripts are equal when they hold the same message objects.
  /// Every change replaces the message it changes, so a changed transcript
  /// never compares equal to the one it came from.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transcript &&
          const ListEquality<Message>().equals(messages, other.messages) &&
          const MapEquality<String, OpenToolCall>()
              .equals(openToolCalls, other.openToolCalls) &&
          const SetEquality<String>()
              .equals(endedToolCallIds, other.endedToolCallIds);

  @override
  int get hashCode => Object.hash(
        const ListEquality<Message>().hash(messages),
        const MapEquality<String, OpenToolCall>().hash(openToolCalls),
        const SetEquality<String>().hash(endedToolCallIds),
      );
}
