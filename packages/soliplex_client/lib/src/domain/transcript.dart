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
/// Starts empty and only grows: every change appends a message or replaces
/// one in place, so the count a backend sees never falls.
@immutable
class Transcript {
  /// Creates an empty transcript.
  const Transcript()
      : messages = const [],
        openToolCalls = const {},
        unansweredToolCallIds = const {};

  Transcript._(
    List<Message> messages,
    Map<String, OpenToolCall> openToolCalls,
    Set<String> unansweredToolCallIds,
  )   : messages = UnmodifiableListView(messages),
        openToolCalls = UnmodifiableMapView(openToolCalls),
        unansweredToolCallIds = UnmodifiableSetView(unansweredToolCallIds);

  /// The messages to send.
  final List<Message> messages;

  /// Calls started and not yet ended, by id. A call joins its parent only
  /// when it ends, so one that never ends is never sent.
  final Map<String, OpenToolCall> openToolCalls;

  /// Ids of calls that joined their parent and have no result yet: the calls
  /// a result may answer. A call starting under an id removes it until that
  /// call ends, so an earlier call's end never vouches for a later one that
  /// reused its id; its result removes it again, so a call takes one result.
  final Set<String> unansweredToolCallIds;

  /// Returns a copy with [message] appended.
  @internal
  Transcript withAppendedMessage(Message message) =>
      copyWith(messages: [...messages, message]);

  /// Creates a copy with the given fields replaced.
  @internal
  Transcript copyWith({
    List<Message>? messages,
    Map<String, OpenToolCall>? openToolCalls,
    Set<String>? unansweredToolCallIds,
  }) =>
      Transcript._(
        messages ?? this.messages,
        openToolCalls ?? this.openToolCalls,
        unansweredToolCallIds ?? this.unansweredToolCallIds,
      );
}
