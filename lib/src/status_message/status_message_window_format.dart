import '../shared/local_time_format.dart';

String _stamp(DateTime local) =>
    '${weekdayAbbrev(local)}, ${monthAbbrev(local)} ${local.day} · '
    '${formatClock12(local)}';

/// Combined local-time label for a maintenance window.
///
/// Same day collapses to one date with an en-dash time range (the CLDR interval
/// convention — the date governs the whole range once); a window that spans
/// days spells out both ends joined by "to" (the style-guide separator for
/// spelled-out ranges):
///
/// - same day → `"Fri, Jul 17 · 4:44 PM – 6:44 PM"`
/// - spanning → `"Fri, Jul 17 · 4:44 PM to Sat, Jul 18 · 3:16 AM"`
///
/// When [stacked] is true, a spanning range breaks after "to" so the end date
/// starts its own line (readable on narrow viewports without a mid-date wrap).
/// [stacked] has no effect on a same-day range.
String formatWindowRange(DateTime start, DateTime end, {bool stacked = false}) {
  final ls = start.toLocal();
  final le = end.toLocal();
  if (isSameCalendarDay(start, end)) {
    return '${_stamp(ls)} – ${formatClock12(le)}';
  }
  final joiner = stacked ? 'to\n' : 'to ';
  return '${_stamp(ls)} $joiner${_stamp(le)}';
}
