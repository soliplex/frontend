import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'ui/execution/timeline_entry.dart';

class ExecutionTracker {
  ExecutionTracker({
    required ReadonlySignal<ExecutionEvent?> executionEvents,
    required Logger logger,
  })  : _logger = logger,
        _historical = false {
    _stopwatch.start();
    _unsub = executionEvents.subscribe(_onEvent);
  }

  /// Builds a frozen tracker seeded from a list of already-emitted
  /// execution events — used on the reload path to reconstruct the
  /// timeline for a completed run.
  ///
  /// The tracker opens no subscription; callers should not pass the
  /// returned instance to any signal. It is immutable from construction
  /// ([isFrozen] returns `true`).
  ExecutionTracker.historical({
    required List<ExecutionEvent> events,
    required Logger logger,
  })  : _logger = logger,
        _historical = true {
    _stopwatch.start();
    for (final event in events) {
      _onEvent(event);
    }
    freeze();
  }

  final Logger _logger;

  /// True when this tracker is replaying stored events on the reload
  /// path. Live-only side-effects (e.g. warning-level logs that mirror a
  /// canonical Sentry event) are gated so they don't fire N times for
  /// every thread reload.
  final bool _historical;

  final Stopwatch _stopwatch = Stopwatch();
  void Function()? _unsub;
  bool _isFrozen = false;
  bool get isFrozen => _isFrozen;

  final Signal<List<ExecutionStep>> _steps =
      Signal<List<ExecutionStep>>(const []);
  ReadonlySignal<List<ExecutionStep>> get steps => _steps;

  final Signal<List<String>> _thinkingBlocks = Signal<List<String>>(const []);
  ReadonlySignal<List<String>> get thinkingBlocks => _thinkingBlocks;

  final Signal<bool> _isThinkingStreaming = Signal<bool>(false);
  ReadonlySignal<bool> get isThinkingStreaming => _isThinkingStreaming;

  /// Decoded `skill_tool_call` activities in arrival order, keyed by
  /// `messageId`. Records that fail to decode as a skill_tool_call are
  /// dropped from this signal (but their raw form is still emitted on
  /// [executionEvents]). Mirrors the upsert semantics of
  /// `Conversation.activities` in soliplex_client.
  final Signal<List<SkillToolCallActivity>> _skillToolCalls =
      Signal<List<SkillToolCallActivity>>(const []);
  ReadonlySignal<List<SkillToolCallActivity>> get skillToolCalls =>
      _skillToolCalls;

  /// Timeline of steps with their nested activities, in arrival order.
  /// Activities that arrive while a step is active are nested under that
  /// step; activities arriving outside any active step are emitted as
  /// [TimelineStandaloneActivity].
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
    _stopwatch.stop();
    _isFrozen = true;
  }

  void _onEvent(ExecutionEvent? event) {
    assert(!_isFrozen, 'Cannot process events on a frozen ExecutionTracker');
    if (event == null) return;
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
      case ActivitySnapshot(
          :final messageId,
          :final activityType,
          :final content,
          :final timestamp,
          :final replace,
        ):
        _upsertSkillToolCall(
          messageId: messageId,
          activityType: activityType,
          content: content,
          timestamp: timestamp,
          replace: replace,
        );
      case TextDelta() ||
            StateUpdated() ||
            StepProgress() ||
            AwaitingApproval() ||
            CustomExecutionEvent():
        break;
    }
  }

  void _upsertSkillToolCall({
    required String messageId,
    required String activityType,
    required Map<String, dynamic> content,
    required int? timestamp,
    required bool replace,
  }) {
    final current = _skillToolCalls.value;
    final existingIndex = current.indexWhere((a) => a.messageId == messageId);

    if (existingIndex >= 0 && !replace) {
      return;
    }

    final record = ActivityRecord(
      messageId: messageId,
      activityType: activityType,
      content: content,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );
    final decoded = SkillToolCallActivity.fromRecord(record);
    if (decoded == null) {
      _logger.warning(
        'SkillToolCallActivity.fromRecord returned null; activity dropped',
        attributes: {
          'messageId': messageId,
          'activityType': activityType,
          'contentKeys': content.keys.toList().toString(),
        },
      );
      return;
    }

    if (existingIndex >= 0) {
      _skillToolCalls.value = [...current]..[existingIndex] = decoded;
    } else {
      _skillToolCalls.value = [...current, decoded];
    }
    _upsertActivityInTimeline(decoded);
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
    assert(!_isFrozen, 'Cannot complete steps on a frozen ExecutionTracker');
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

  void _upsertActivityInTimeline(SkillToolCallActivity decoded) {
    final current = _timeline.value;
    for (var i = 0; i < current.length; i++) {
      final entry = current[i];
      if (entry is TimelineStep) {
        final aIdx = entry.activities
            .indexWhere((a) => a.messageId == decoded.messageId);
        if (aIdx >= 0) {
          final updated = [...entry.activities]..[aIdx] = decoded;
          _timeline.value = [...current]..[i] = entry.withActivities(updated);
          return;
        }
      } else if (entry is TimelineStandaloneActivity &&
          entry.activity.messageId == decoded.messageId) {
        _timeline.value = [...current]..[i] =
            TimelineStandaloneActivity(activity: decoded);
        return;
      }
    }
    if (current.isNotEmpty && current.last is TimelineStep) {
      final lastStep = current.last as TimelineStep;
      if (lastStep.step.status == StepStatus.active) {
        _timeline.value = [...current]..[current.length - 1] =
            lastStep.withActivities([...lastStep.activities, decoded]);
        return;
      }
    }
    _timeline.value = [
      ...current,
      TimelineStandaloneActivity(activity: decoded)
    ];
  }

  void dispose() {
    _unsub?.call();
    _unsub = null;
    _stopwatch.stop();
  }
}
