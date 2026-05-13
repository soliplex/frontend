import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'ui/execution/timeline_entry.dart';

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
  ExecutionTracker.historical({
    required List<ExecutionEvent> events,
    required List<ActivityRecord> activities,
    required Logger logger,
  })  : _logger = logger,
        _activities = Signal<List<ActivityRecord>>(activities),
        _historical = true {
    _stopwatch.start();
    for (final event in events) {
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

  final Stopwatch _stopwatch = Stopwatch();
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

  /// Decoded skill_tool activities, derived reactively from the source
  /// activities signal. Records that fail to decode as a skill_tool_*
  /// view are filtered out. The list mirrors the source order in
  /// `Conversation.activities`.
  late final ReadonlySignal<List<SkillToolCallActivity>> skillToolCalls =
      computed(() {
    return [
      for (final record in _activities.value)
        if (SkillToolCallActivity.fromRecord(record) case final view?) view,
    ];
  });

  /// Timeline of steps with their nested activity ids, in arrival
  /// order. Activities that arrive while a step is active are nested
  /// under that step; activities arriving outside any active step are
  /// emitted as [TimelineStandaloneActivity]. The renderer resolves
  /// each id against [skillToolCalls] at paint time.
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
      case ServerToolCallStarted(:final toolName):
        _completeActiveStep();
        _isThinkingStreaming.value = false;
        _addStep(toolName, StepType.toolCall);
      case ServerToolCallCompleted():
        _completeActiveStep();
      case ClientToolExecuting(:final toolName):
        _completeActiveStep();
        _isThinkingStreaming.value = false;
        _addStep(toolName, StepType.toolCall);
      case ClientToolCompleted():
        _completeActiveStep();
      case RunCompleted():
        _completeAllSteps(StepStatus.completed);
        _isThinkingStreaming.value = false;
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
      case ActivitySnapshot(:final messageId, :final activityType):
        // Only place ids whose activityType the decoder recognises. Other
        // types still persist into Conversation.activities at the domain
        // layer (so future consumers can read them), but they don't get a
        // timeline row — placing them would produce a phantom entry whose
        // _resolveActivity returns null on every render.
        if (kSkillToolCallActivityTypes.contains(activityType)) {
          _placeActivityInTimeline(messageId);
        }
      case TextDelta() ||
            StateUpdated() ||
            StepProgress() ||
            AwaitingApproval() ||
            CustomExecutionEvent():
        break;
    }
  }

  /// Records the structural position of [activityId] in the timeline.
  /// Content is sourced from [skillToolCalls]; this only decides which
  /// step the row nests under (or whether it stands alone). An id
  /// already present in any entry is a no-op — the activity updates in
  /// place via the computed signal.
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

  void _addStep(String label, StepType type) {
    final step = ExecutionStep(
      label: label,
      type: type,
      status: StepStatus.active,
      timestamp: _stopwatch.elapsed,
    );
    _steps.value = [..._steps.value, step];
    _timeline.value = [..._timeline.value, TimelineStep(step: step)];
  }

  void _completeActiveStep() {
    final current = _steps.value;
    if (current.isEmpty) return;
    final last = current.last;
    if (last.status == StepStatus.active) {
      final updated = last.copyWith(
        status: StepStatus.completed,
        timestamp: _stopwatch.elapsed,
      );
      _steps.value = [...current.sublist(0, current.length - 1), updated];
      _updateLastActiveStepInTimeline(updated);
    }
  }

  void _completeAllSteps(StepStatus status) {
    final now = _stopwatch.elapsed;
    _steps.value = [
      for (final step in _steps.value)
        step.status == StepStatus.active
            ? step.copyWith(status: status, timestamp: now)
            : step,
    ];
    _timeline.value = [
      for (final entry in _timeline.value)
        if (entry is TimelineStep && entry.step.status == StepStatus.active)
          entry.withStep(entry.step.copyWith(status: status, timestamp: now))
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
