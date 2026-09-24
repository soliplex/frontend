/// The AG-UI state a run carries for how hard its model thinks.
///
/// `thinking` is the one AG-UI feature the client owns rather than reads: the
/// RAG namespaces are accumulated by the backend and carried back untouched,
/// while this one travels the other way. The backend keeps the last value with
/// the run that carried it, so a thread's level is read back from its newest
/// run input rather than from any state event.
library;

/// The state-namespace key the backend registers this feature under.
const String thinkingStateNamespace = 'thinking';

/// The state field carrying the level.
const String thinkingLevelKey = 'level';

/// Builds the AG-UI state overlay asserting [level] for a run.
///
/// [level] must be one the room offers — `Room.agent`'s `thinking.levels`, and
/// nothing else. The backend refuses a level its room does not offer, because
/// which levels a model accepts belongs to its chat template and a rejected
/// one fails the run.
///
/// A null [level] is asserted rather than omitted: it is what clears a
/// narrower level the thread's cached state may still carry from an earlier
/// turn, leaving the room's own default in force.
Map<String, dynamic> buildThinkingStateOverlay(String? level) {
  return {
    thinkingStateNamespace: <String, dynamic>{thinkingLevelKey: level},
  };
}

/// Reads the level out of one run's `run_input.state`, or null when it
/// carries none.
///
/// Tolerant by design: this reads a payload the client did not build, and a
/// shape it does not recognise means "nothing asserted" rather than an error.
String? thinkingLevelFromState(Object? state) {
  if (state is! Map<String, dynamic>) return null;
  final namespace = state[thinkingStateNamespace];
  if (namespace is! Map<String, dynamic>) return null;
  final level = namespace[thinkingLevelKey];
  return level is String ? level : null;
}
