import '../shared/local_time_format.dart';

String _dateLabel(DateTime local) =>
    '${weekdayAbbrev(local)}, ${monthAbbrev(local)} ${local.day}';

/// Local-time label for a window bound, e.g. `"Sun, Jun 28 · 1:16 PM"`.
///
/// When [sameDayAs] falls on the same local calendar day, the date is omitted
/// and only the time is returned (e.g. `"3:16 PM"`).
String formatWindowBound(DateTime bound, {DateTime? sameDayAs}) {
  final local = bound.toLocal();
  final time = formatClock12(local);
  if (sameDayAs != null && isSameCalendarDay(bound, sameDayAs)) {
    return time;
  }
  return '${_dateLabel(local)} · $time';
}
