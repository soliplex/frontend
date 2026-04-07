import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';

class ExecutionTracker {
  ExecutionTracker({
    required ReadonlySignal<ExecutionEvent?> executionEvents,
  }) {
    _stopwatch.start();
    _unsub = executionEvents.subscribe(_onEvent);
  }

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

  void freeze() {
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
      case RunFailed() || RunCancelled():
        _completeAllSteps(StepStatus.failed);
        _isThinkingStreaming.value = false;
      case TextDelta() ||
            StateUpdated() ||
            StepProgress() ||
            AwaitingApproval() ||
            ActivitySnapshot() ||
            CustomExecutionEvent():
        break;
    }
  }

  void _addStep(String label, StepType type) {
    _steps.value = [
      ..._steps.value,
      ExecutionStep(
        label: label,
        type: type,
        status: StepStatus.active,
        timestamp: _stopwatch.elapsed,
      ),
    ];
  }

  void _completeActiveStep() {
    final current = _steps.value;
    if (current.isEmpty) return;
    final last = current.last;
    if (last.status == StepStatus.active) {
      _steps.value = [
        ...current.sublist(0, current.length - 1),
        last.copyWith(
          status: StepStatus.completed,
          timestamp: _stopwatch.elapsed,
        ),
      ];
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
  }

  void dispose() {
    _unsub?.call();
    _unsub = null;
    _stopwatch.stop();
  }
}
