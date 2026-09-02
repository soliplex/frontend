import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'ui/execution/timeline_entry.dart';

/// A bridged execution event paired with the epoch-millisecond emission time
/// of the AG-UI event it came from, or null when that event carried none.
typedef TimedExecutionEvent = ({ExecutionEvent event, int? timestamp});

class ExecutionTracker {
  ExecutionTracker({
    required ReadonlySignal<ExecutionEvent?> executionEvents,
    required ReadonlySignal<List<ActivityRecord>> activities,
    required Logger logger,
  })  : _logger = logger,
        _activities = Signal<List<ActivityRecord>>(activities.value),
        _historical = false {
    _stopwatch.start();
    _unsub = executionEvents.subscribe(_onEvent);
    // Mirror the session-owned activities into our local signal so the
    // tracker stays self-contained when ThreadViewState absorbs it on
    // detach: freeze() drops the subscription, and the captured list
    // outlives the session's signal teardown.
    _activitiesUnsub = activities.subscribe((value) {
      _activities.value = value;
    });
  }

  /// Builds a frozen tracker seeded from a list of already-emitted
  /// execution events — used on the reload path to reconstruct the
  /// timeline for a completed run.
  ///
  /// The tracker opens no subscription; callers should not pass the
  /// returned instance to any signal. It is immutable from construction
  /// ([isFrozen] returns `true`). [activities] is the already-folded
  /// activities list (see `applyActivityEvent`) — historical replay
  /// folds the raw AG-UI events through the same function the live
  /// processor uses, so snapshot + delta application produces the same
  /// result as a live run with the same event stream.
  ///
  /// Step offsets are measured from [origin], the epoch-millisecond instant
  /// this tracker's stretch of the run began: a clock started here would time
  /// the replay loop, not the run it is replaying. Callers take [origin] from
  /// the first stored event of the same bucket, including the ones that bridge
  /// to nothing, so it lands on the start of that stretch rather than on the
  /// first event that happens to carry an execution step. Null leaves every
  /// offset unknown, which is a bucket whose stored events carry no time at
  /// all — no stretch of it can be placed.
  ///
  /// An entry with no emission time leaves the offset unknown for as long as
  /// it is the one being handled. Its step opens, or settles, with no figure:
  /// a run interrupted mid-call emits its tool result unstamped, and carrying
  /// the previous offset forward would settle that step at the instant it
  /// opened.
  ExecutionTracker.historical({
    required List<TimedExecutionEvent> events,
    required int? origin,
    required List<ActivityRecord> activities,
    required Logger logger,
  })  : _logger = logger,
        _activities = Signal<List<ActivityRecord>>(activities),
        _historical = true {
    for (final (:event, :timestamp) in events) {
      _replayOffset = (timestamp == null || origin == null)
          ? null
          : Duration(milliseconds: timestamp - origin);
      _onEvent(event);
    }
    freeze();
  }

  final Logger _logger;
  final Signal<List<ActivityRecord>> _activities;

  /// True when this tracker is replaying stored events on the reload
  /// path. Live-only side-effects (e.g. warning-level logs that mirror a
  /// canonical Sentry event) are gated so they don't fire N times for
  /// every thread reload.
  final bool _historical;

  /// `<toolCallId>#<phase>` keys already reported as having no step, so one
  /// call's delta stream logs once rather than per delta.
  final Set<String> _loggedUnmatchedCalls = <String>{};

  /// Tool call ids already reported as finishing a run without a result.
  final Set<String> _reportedMissingResults = <String>{};

  final Stopwatch _stopwatch = Stopwatch();

  /// Where the event being replayed sits relative to the tracker's anchor,
  /// or null when that event carried no emission time. Rewritten for every
  /// entry rather than retained, so an unstamped event yields no figure
  /// instead of repeating the previous one. Unused on the live path, which
  /// reads the running clock instead.
  Duration? _replayOffset;

  /// The offset to stamp on a step changing now: the running clock on the
  /// live path, and on the replay path the offset of the event being handled
  /// — or, once the loop has finished, of the last one.
  Duration? get _now => _historical ? _replayOffset : _stopwatch.elapsed;

  void Function()? _unsub;
  void Function()? _activitiesUnsub;
  bool _isFrozen = false;
  bool get isFrozen => _isFrozen;

  final Signal<List<ExecutionStep>> _steps =
      Signal<List<ExecutionStep>>(const []);
  ReadonlySignal<List<ExecutionStep>> get steps => _steps;

  final Signal<List<String>> _thinkingBlocks = Signal<List<String>>(const []);
  ReadonlySignal<List<String>> get thinkingBlocks => _thinkingBlocks;

  final Signal<bool> _isThinkingStreaming = Signal<bool>(false);
  ReadonlySignal<bool> get isThinkingStreaming => _isThinkingStreaming;

  /// The activity records this tracker's timeline resolves against, in
  /// the source order of `Conversation.activities`. Content is stored as
  /// the backend sent it — AG-UI defines an activity's `content` as
  /// opaque, so the renderer, not this layer, decides how to read it.
  ReadonlySignal<List<ActivityRecord>> get activities => _activities;

  /// Timeline of steps with their nested activity ids, in arrival
  /// order. Activities that arrive while a step is active are nested
  /// under that step; activities arriving outside any active step are
  /// emitted as [TimelineStandaloneActivity]. The renderer resolves
  /// each id against [activities] at paint time.
  final Signal<List<TimelineEntry>> _timeline =
      Signal<List<TimelineEntry>>(const []);
  ReadonlySignal<List<TimelineEntry>> get timeline => _timeline;

  /// Marks the tracker terminal: clears the spinner, completes any
  /// still-active steps, and releases the subscription. Idempotent.
  void freeze() {
    if (_isFrozen) return;
    _isThinkingStreaming.value = false;
    _completeAllSteps(StepStatus.completed);
    _unsub?.call();
    _unsub = null;
    _activitiesUnsub?.call();
    _activitiesUnsub = null;
    _stopwatch.stop();
    _isFrozen = true;
  }

  void _onEvent(ExecutionEvent? event) {
    assert(!_isFrozen, 'Cannot process events on a frozen ExecutionTracker');
    if (event == null) return;
    try {
      _dispatch(event);
    } on Object catch (e, st) {
      // `_dispatch` operates on already-decoded `ExecutionEvent` variants
      // and mutates local signals — a throw here is a frontend logic bug
      // (bad cast, signals misuse, missing switch arm), not backend drift.
      // Swallow in prod so downstream observers stay alive, but fail loud
      // in dev/test via assert so the bug surfaces immediately.
      _logger.error(
        'ExecutionTracker dropped ${event.runtimeType}',
        error: e,
        stackTrace: st,
        attributes: {'errorType': e.runtimeType.toString()},
      );
      assert(
        false,
        'ExecutionTracker._dispatch threw: $e\n$st',
      );
    }
  }

  void _dispatch(ExecutionEvent event) {
    switch (event) {
      case ThinkingStarted():
        _completeActiveStep();
        _addStep('Thinking', StepType.thinking);
        _thinkingBlocks.value = [..._thinkingBlocks.value, ''];
        _isThinkingStreaming.value = true;
      case ThinkingContent(:final delta):
        final blocks = _thinkingBlocks.value;
        if (blocks.isNotEmpty) {
          _thinkingBlocks.value = [
            ...blocks.sublist(0, blocks.length - 1),
            blocks.last + delta,
          ];
        }
      case ThinkingEnded():
        // Don't complete the active step here: backends emit
        // ThinkingEnded between thinking and an immediately-following
        // tool call, and completing the step now would split a single
        // logical step into two timeline entries.
        _isThinkingStreaming.value = false;
      case ServerToolCallStarted(:final toolName, :final toolCallId):
        _completeActiveStep();
        _isThinkingStreaming.value = false;
        _addStep(toolName, StepType.toolCall, toolCallId: toolCallId);
      case ServerToolCallArgs(:final toolCallId, :final delta):
        _appendCallArgs(toolCallId, delta);
      case ServerToolCallCompleted(:final toolCallId, :final result):
        _completeCall(toolCallId, result);
      case ClientToolExecuting(:final toolName):
        _completeActiveStep();
        _isThinkingStreaming.value = false;
        _addStep(toolName, StepType.toolCall);
      case ClientToolCompleted():
        _completeActiveStep();
      case RunCompleted():
        _completeAllSteps(StepStatus.completed);
        _isThinkingStreaming.value = false;
        _reportCallsMissingResult();
      case RunFailed(:final error):
        // Backend RunErrorEvent surfaces here as `RunFailed`. The
        // application layer (`agui_event_processor._processRunError`) only
        // logs at info on the synthesis-decline path, and
        // `RunOrchestrator._onStreamError` only fires for stream-level
        // failures — so this is the canonical warning-level signal.
        // Skip on historical replay so reloads don't multiply the entry.
        if (!_historical) {
          _logger.warning(
            'Tracker observed run failure',
            attributes: {'error': error},
          );
        }
        _completeAllSteps(StepStatus.failed);
        _isThinkingStreaming.value = false;
      case RunCancelled():
        _completeAllSteps(StepStatus.failed);
        _isThinkingStreaming.value = false;
      case ActivitySnapshot(:final messageId):
        _placeActivityInTimeline(messageId);
      case TextDelta() ||
            StateUpdated() ||
            StepProgress() ||
            AwaitingApproval() ||
            CustomExecutionEvent():
        break;
    }
  }

  /// Records the structural position of [activityId] in the timeline.
  /// Content is sourced from [activities]; this only decides which step
  /// the row nests under (or whether it stands alone). An id already
  /// present in any entry is a no-op — the activity updates in place
  /// through the signal.
  void _placeActivityInTimeline(String activityId) {
    final current = _timeline.value;
    for (final entry in current) {
      if (entry is TimelineStep && entry.activityIds.contains(activityId)) {
        return;
      }
      if (entry is TimelineStandaloneActivity &&
          entry.activityId == activityId) {
        return;
      }
    }
    if (current.isNotEmpty && current.last is TimelineStep) {
      final lastStep = current.last as TimelineStep;
      if (lastStep.step.status == StepStatus.active) {
        _timeline.value = [...current]..[current.length - 1] =
            lastStep.withActivities([...lastStep.activityIds, activityId]);
        return;
      }
    }
    _timeline.value = [
      ...current,
      TimelineStandaloneActivity(activityId: activityId),
    ];
  }

  /// Appends an args delta to the step opened by [toolCallId].
  ///
  /// A delta for an id with no step — no `TOOL_CALL_START` was observed for it,
  /// because it was dropped or the stream resumed mid-call — has nowhere to go
  /// and is discarded with a one-time warning.
  void _appendCallArgs(String toolCallId, String delta) {
    final match = _findCall(toolCallId);
    if (match == null) {
      // The client layer's warning for this condition tests a weaker
      // predicate — one `Conversation` spans a whole thread, while a tracker
      // holds one message's bucket — so a call whose start landed in another
      // bucket is unmatched here and known there. Report it on the replay
      // path too, or that delta is lost with no trace anywhere.
      _reportUnmatchedCall(toolCallId, 'args');
      return;
    }
    _replaceEntry(match, match.entry.appendArgs(delta));
  }

  /// Attaches [result] to the call opened by [toolCallId] and completes that
  /// call's step.
  ///
  /// Completion is by id rather than by position: a toolset that does not
  /// declare itself sequential can overlap calls, and settling the newest
  /// active step instead would put the result on one row and its check mark on
  /// another.
  void _completeCall(String toolCallId, String result) {
    final match = _findCall(toolCallId);
    if (match == null) {
      // No client-layer log covers an unmatched result — `_processToolCallArgs`
      // warns but `_processToolCallResult` does not — so report it on the
      // replay path too, or a stored thread that lost one is silent everywhere.
      _reportUnmatchedCall(toolCallId, 'result');
      // Deliberately settles nothing: the step this result belongs to is not
      // in the timeline, so any row settled here would be another call's.
      // Every terminal path completes what is still active anyway.
      return;
    }

    final entry = match.entry;
    final step = entry.step;
    final completed = step.status == StepStatus.active
        ? step.settled(status: StepStatus.completed, at: _now)
        : step;
    _replaceEntry(match, entry.withResult(result).withStep(completed));
    if (!identical(completed, step)) {
      _steps.value = [
        for (final candidate in _steps.value)
          identical(candidate, step) ? completed : candidate,
      ];
    }

    if (_historical) return;
    // Confirms the detail reached the row, which is the question to ask when a
    // source block comes up empty. Lengths only: the args carry the user's
    // query and the result carries retrieved document text.
    _logger.info(
      'Timeline detail: ${entry.step.label} captured '
      '${entry.args.length} args chars, ${result.length} result chars.',
    );
  }

  /// A run that finished successfully having opened a call whose result never
  /// arrived has lost detail in transit. Reported on the replay path as well,
  /// because a stored thread missing a result has no other trace.
  ///
  /// Scans the whole timeline rather than one run's slice, since a run's steps
  /// are not delimited here — so each id is reported at most once, or a replay
  /// bucket holding several runs would re-report an earlier run's gap at every
  /// later run's completion.
  void _reportCallsMissingResult() {
    final missing = <String>[];
    for (final entry in _timeline.value) {
      if (entry is! TimelineStep) continue;
      final id = entry.toolCallId;
      if (id == null || entry.result != null) continue;
      if (_reportedMissingResults.add(id)) missing.add(entry.step.label);
    }
    if (missing.isEmpty) return;
    _logger.warning(
      'ExecutionTracker: run completed with tool call(s) whose result never '
      'arrived; their rows render without a result.',
      attributes: {'tools': missing.join(', '), 'count': missing.length},
    );
  }

  /// The most recently opened step carrying [toolCallId] and where it sits, or
  /// null when no step does.
  ///
  /// Searched newest-first because the reload path can bucket several runs'
  /// events into one tracker, and a provider that reuses call ids across runs
  /// would otherwise attach the later run's detail to the earlier run's step.
  ///
  /// Carries the position so [_replaceEntry] writes to the step that was
  /// found, rather than re-deriving it by searching for an equal one.
  ({int index, TimelineStep entry})? _findCall(String toolCallId) {
    final current = _timeline.value;
    for (var i = current.length - 1; i >= 0; i--) {
      final entry = current[i];
      if (entry is TimelineStep && entry.toolCallId == toolCallId) {
        return (index: i, entry: entry);
      }
    }
    return null;
  }

  void _replaceEntry(
    ({int index, TimelineStep entry}) at,
    TimelineStep updated,
  ) {
    _timeline.value = [..._timeline.value]..[at.index] = updated;
  }

  /// Reports detail that arrived for a call with no step, once per id and
  /// phase. Warning level so it survives the release floor; throttled so a
  /// delta stream cannot flood the sink, and keyed by phase so a lost result is
  /// still reported for an id whose args were already lost.
  void _reportUnmatchedCall(String toolCallId, String phase) {
    if (!_loggedUnmatchedCalls.add('$toolCallId#$phase')) return;
    _logger.warning(
      'ExecutionTracker: tool call $phase arrived for an id with no step; '
      'the row will render without it.',
      attributes: {
        'toolCallId': toolCallId,
        'phase': phase,
        'stepCount': _timeline.value.whereType<TimelineStep>().length,
      },
    );
  }

  void _addStep(String label, StepType type, {String? toolCallId}) {
    final step = ExecutionStep(
      label: label,
      type: type,
      status: StepStatus.active,
      timestamp: _now,
    );
    _steps.value = [..._steps.value, step];
    _timeline.value = [
      ..._timeline.value,
      TimelineStep(step: step, toolCallId: toolCallId),
    ];
  }

  void _completeActiveStep() {
    final current = _steps.value;
    if (current.isEmpty) return;
    final last = current.last;
    if (last.status == StepStatus.active) {
      final updated = last.settled(status: StepStatus.completed, at: _now);
      _steps.value = [...current.sublist(0, current.length - 1), updated];
      _updateLastActiveStepInTimeline(updated);
    }
  }

  void _completeAllSteps(StepStatus status) {
    final now = _now;
    _steps.value = [
      for (final step in _steps.value)
        step.status == StepStatus.active
            ? step.settled(status: status, at: now)
            : step,
    ];
    _timeline.value = [
      for (final entry in _timeline.value)
        if (entry is TimelineStep && entry.step.status == StepStatus.active)
          entry.withStep(entry.step.settled(status: status, at: now))
        else
          entry,
    ];
  }

  void _updateLastActiveStepInTimeline(ExecutionStep updated) {
    final current = _timeline.value;
    for (var i = current.length - 1; i >= 0; i--) {
      final entry = current[i];
      if (entry is TimelineStep && entry.step.status == StepStatus.active) {
        _timeline.value = [...current]..[i] = entry.withStep(updated);
        return;
      }
    }
  }

  void dispose() {
    _unsub?.call();
    _unsub = null;
    _activitiesUnsub?.call();
    _activitiesUnsub = null;
    _stopwatch.stop();
  }
}
