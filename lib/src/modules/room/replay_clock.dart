/// Times a replayed band's steps by the stored events being fed, as a live
/// band times them by a running clock.
///
/// A band's offsets count from the stored event being fed when it opened, or,
/// when that event carries no time, from the next one that does. That event
/// can be one that bridges to no step, as the one opening a stretch of the run
/// often is.
class ReplayClock {
  int? _now;
  final List<void Function(int)> _waitingForTime = [];

  /// The emission time of the stored event about to be fed, in epoch
  /// milliseconds, or null when that event carries none.
  set eventTime(int? time) {
    _now = time;
    if (time == null) return;
    for (final start in _waitingForTime) {
      start(time);
    }
    _waitingForTime.clear();
  }

  /// Starts timing a band opened now; the returned function reads how far
  /// into it the event being fed is, or null when that is unknown.
  Duration? Function() start() {
    var origin = _now;
    if (origin == null) _waitingForTime.add((time) => origin = time);
    return () {
      final now = _now;
      final from = origin;
      if (now == null || from == null) return null;
      return Duration(milliseconds: now - from);
    };
  }
}
