import 'dart:async';

/// Coalesces a burst of calls into a single trailing invocation: each [run]
/// cancels the pending action and reschedules, so [action] fires once,
/// [duration] after the most recent call. The latest call always wins, which
/// guarantees the final state is the one acted on.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
