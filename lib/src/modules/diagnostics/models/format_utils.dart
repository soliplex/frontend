extension HttpTimestampFormat on DateTime {
  String toHttpTimeString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final s = second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

extension HttpDurationFormat on Duration {
  static const _msPerSecond = 1000;
  static const _msPerMinute = 60000;

  String toHttpDurationString() {
    final ms = inMilliseconds;
    if (ms < _msPerSecond) return '${ms}ms';
    if (ms < _msPerMinute) return '${(ms / _msPerSecond).toStringAsFixed(1)}s';
    return '${(ms / _msPerMinute).toStringAsFixed(1)}m';
  }
}

extension HttpBytesFormat on int {
  static const _bytesPerKB = 1024;
  static const _bytesPerMB = 1024 * 1024;

  String toHttpBytesString() {
    if (this < _bytesPerKB) return '${this}B';
    if (this < _bytesPerMB) {
      return '${(this / _bytesPerKB).toStringAsFixed(1)}KB';
    }
    return '${(this / _bytesPerMB).toStringAsFixed(1)}MB';
  }
}
