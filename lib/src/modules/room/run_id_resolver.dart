import 'package:soliplex_agent/soliplex_agent.dart';

/// The run a tile's actions belong to — reporting a problem, submitting
/// feedback, inspecting the exchange, listing the files a run wrote.
///
/// An assistant tile names the run that produced it and nothing else. Reaching
/// back to the user message before it would file an early segment's reply under
/// whichever run happened to finish the turn, because that message's
/// association deliberately advances to the last segment of a tool loop.
///
/// A user tile is the exception, and takes that association first. Its own run
/// is the one it opened, which is not the run its actions should reach: a
/// reader reporting a problem with a turn means the turn, not its first
/// segment. Its own run is the fallback for a message nothing associated —
/// live, the optimistic echo carries none at all, because it exists before the
/// run it starts.
///
/// Both paths therefore resolve a user tile the same way, which is what keeps
/// the action it offers from depending on whether the thread has been
/// reloaded.
String? resolveRunId(
  ChatMessage message,
  Map<String, MessageState> messageStates,
) =>
    message.user == ChatUser.user
        ? messageStates[message.id]?.runId ?? message.runId
        : message.runId;
