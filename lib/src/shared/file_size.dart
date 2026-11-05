const _units = [
  (short: 'B', spoken: 'byte'),
  (short: 'KB', spoken: 'kilobyte'),
  (short: 'MB', spoken: 'megabyte'),
  (short: 'GB', spoken: 'gigabyte'),
  (short: 'TB', spoken: 'terabyte'),
];

/// [bytes] counted in 1024s, as `512 B`, `2.4 KB`, `12 KB` or `3.1 MB`: one
/// decimal under ten, none from ten up or when that decimal is zero.
String formatFileSize(int bytes) {
  final (number, unit) = _scaled(bytes);
  return '$number ${unit.short}';
}

/// [formatFileSize] for a screen reader, with the unit in words:
/// `2.4 kilobytes`, `1 byte`.
String spokenFileSize(int bytes) {
  final (number, unit) = _scaled(bytes);
  return '$number ${unit.spoken}${number == '1' ? '' : 's'}';
}

(String, ({String short, String spoken})) _scaled(int bytes) {
  var value = bytes.toDouble();
  var i = 0;
  while (i < _units.length - 1 && _rounded(value) >= 1024) {
    value /= 1024;
    i++;
  }
  return (_shown(value), _units[i]);
}

/// [value] as shown: rounding happens before the unit is chosen, so 1023.96
/// kilobytes shows as `1 MB`, not `1024 KB`.
double _rounded(double value) =>
    value < 9.95 ? (value * 10).round() / 10 : value.roundToDouble();

String _shown(double value) {
  final rounded = _rounded(value);
  return rounded == rounded.truncateToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}
