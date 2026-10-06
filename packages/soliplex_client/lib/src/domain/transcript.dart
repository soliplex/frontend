import 'dart:collection';

import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';

/// A tool call whose start has arrived but not its end, and the assistant
/// message it joins when it ends.
typedef OpenToolCall = ({ToolCall call, String parentId});

/// The AG-UI messages a thread sends as its history — its user messages, the
/// messages its events build, and the tool results supplied for its calls, in
/// the order they arrived — with what building it carries from one event to
/// the next.
///
/// Its messages start empty and only grow: a change appends a message or
/// replaces one in place. A backend that numbers a thread's questions by
/// message count needs the count to grow.
@immutable
final class Transcript {
  /// Creates an empty transcript.
  const Transcript()
      : messages = const [],
        openToolCalls = const {},
        unansweredToolCallIds = const {};

  const Transcript._(
    this.messages,
    this.openToolCalls,
    this.unansweredToolCallIds,
  );

  /// The messages to send.
  final List<Message> messages;

  /// Calls started and not yet ended, by id. A call joins its parent only
  /// when it ends, so one that never ends is never sent.
  @internal
  final Map<String, OpenToolCall> openToolCalls;

  /// Ids of calls that joined their parent and have no result yet: the calls
  /// a result may answer. A call starting under an id removes it until that
  /// call ends, so an earlier call's end never vouches for a later one that
  /// reused its id; its result removes it again, so a call takes one result.
  @internal
  final Set<String> unansweredToolCallIds;

  /// Returns a copy with [message] appended.
  @internal
  Transcript withAppendedMessage(Message message) => Transcript._(
        UnmodifiableListView([...messages, message]),
        openToolCalls,
        unansweredToolCallIds,
      );

  /// Returns a copy with the message at [index] replaced by [message].
  @internal
  Transcript withReplacedMessage(int index, Message message) => Transcript._(
        UnmodifiableListView([...messages]..[index] = message),
        openToolCalls,
        unansweredToolCallIds,
      );

  /// Creates a copy with the given call bookkeeping replaced; its messages
  /// change only through [withAppendedMessage] and [withReplacedMessage]. Only
  /// a replaced field is wrapped unmodifiable: wrapping a kept one again would
  /// nest a view per change, and a long thread would exhaust the stack
  /// reading through them.
  @internal
  Transcript copyWith({
    Map<String, OpenToolCall>? openToolCalls,
    Set<String>? unansweredToolCallIds,
  }) =>
      Transcript._(
        messages,
        openToolCalls == null
            ? this.openToolCalls
            : UnmodifiableMapView(openToolCalls),
        unansweredToolCallIds == null
            ? this.unansweredToolCallIds
            : UnmodifiableSetView(unansweredToolCallIds),
      );
}
