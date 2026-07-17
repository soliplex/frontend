// Pure, dependency-free local-time formatting primitives (no `intl`). Callers
// pass an already-local `DateTime` (via `.toLocal()`) before reading any
// calendar field, except [isSameCalendarDay], which localizes its own inputs.

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Three-letter weekday for a local date, e.g. `"Mon"`.
String weekdayAbbrev(DateTime local) =>
    weekdayNames[local.weekday - 1].substring(0, 3);

/// Three-letter month for a local date, e.g. `"Jun"`.
String monthAbbrev(DateTime local) =>
    monthNames[local.month - 1].substring(0, 3);

/// 12-hour clock for a local time: midnight → `12:xx AM`, noon → `12:xx PM`,
/// minute zero-padded, hour unpadded.
String formatClock12(DateTime local) {
  final h = local.hour;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  final period = h < 12 ? 'AM' : 'PM';
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hour12:$mm $period';
}

/// Whether [a] and [b] fall on the same local calendar day. Component equality
/// (no arithmetic), so it is DST-safe.
bool isSameCalendarDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}
