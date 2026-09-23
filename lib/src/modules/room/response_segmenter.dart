import 'package:soliplex_agent/soliplex_agent.dart';

/// Whether [event] is the first output of a model response: its reasoning,
/// its text, or its first tool call.
///
/// A tool result ends the response that made the call, but what follows it is
/// not all a new response. State the tool wrote, a result for a call made in
/// parallel, and the run ending all belong to the response being closed. Live
/// and reload both decide where a response ends with this.
bool opensResponse(ExecutionEvent event) => switch (event) {
      ThinkingStarted() || TextDelta() || ServerToolCallStarted() => true,
      ThinkingContent() ||
      ThinkingEnded() ||
      ServerToolCallArgs() ||
      ServerToolCallCompleted() ||
      ClientToolExecuting() ||
      ClientToolCompleted() ||
      RunCompleted() ||
      RunFailed() ||
      RunCancelled() ||
      StateUpdated() ||
      StepProgress() ||
      AwaitingApproval() ||
      ActivitySnapshot() ||
      CustomExecutionEvent() =>
        false,
    };

/// Where a run's work belongs, one model response at a time.
///
/// The producer emits one response at a time — reasoning, then a message, then
/// the tool calls that message asked for — and a tool result ends it: the
/// producer is invoked again to decide what to do with the result, and what it
/// emits next belongs to a new response. The first message to speak in a
/// response speaks for it, and owns the response's work. A
/// response that says nothing leaves its work where it is, so the next one to
/// speak takes that too.
///
/// The live registry and history replay both segment a run through this. They
/// differ only in how they learn a message spoke and in where they keep the
/// work, so each tells this what happened and moves the work where it says.
/// One per run: nothing carries from one run to the next.
class ResponseSegmenter {
  /// The message that has spoken in the response now being collected, or null
  /// while it has said nothing.
  String? get owner => _voice;
  String? _voice;

  /// A tool result arrived and the response that made the call has not ended,
  /// because the next response has not started yet.
  bool _resultPending = false;

  /// [messageId] said something.
  ///
  /// Returns the message the ended response hands its work to, when a message
  /// speaking after a tool result is the next response starting, or null.
  String? speaks(String messageId) {
    final takes = _endIfPending();
    // A producer that emits two texts in one response has not done two things,
    // and splitting the response's work between them would put half of it
    // above a line that did not ask for it.
    _voice ??= messageId;
    return takes;
  }

  /// [event] is about to be recorded against the response being collected.
  ///
  /// Returns the message the ended response hands its work to, when [event]
  /// is the first output of the next response ([opensResponse]), or null.
  String? arrives(ExecutionEvent event) {
    final takes = opensResponse(event) ? _endIfPending() : null;
    if (event is ServerToolCallCompleted) _resultPending = true;
    return takes;
  }

  /// The run ended, and the response being collected ends with it.
  ///
  /// Returns the message that spoke in it, which takes its work, or null when
  /// nothing spoke — the last response of a run has no tool result to end it.
  String? ends() {
    final takes = _voice;
    _voice = null;
    _resultPending = false;
    return takes;
  }

  String? _endIfPending() {
    if (!_resultPending) return null;
    _resultPending = false;
    final takes = _voice;
    _voice = null;
    return takes;
  }
}
