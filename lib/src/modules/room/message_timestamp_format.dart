// Pure formatting for chat message time captions and day dividers.
//
// All inputs are converted to the viewer's local zone before any calendar
// field is read. `now` is injectable for testing. The 12-hour clock,
// weekday/month names, and same-day check come from the shared, dependency-free
// local-time helpers.

import '../../shared/local_time_format.dart';

enum _DayBucket { today, yesterday, weekday, thisYear, older }

/// Whole calendar days between two local dates, computed DST-immune by flooring
/// each to a UTC midnight (UTC has no DST, so the diff is always whole days).
/// Not `now.difference(t).inDays`, which counts 24-hour chunks and both
/// misbuckets near midnight and truncates a 23-hour spring-forward day.
int _daysAgo(DateTime localT, DateTime localNow) {
  final t = DateTime.utc(localT.year, localT.month, localT.day);
  final n = DateTime.utc(localNow.year, localNow.month, localNow.day);
  return n.difference(t).inDays;
}

_DayBucket _bucketFor(DateTime localT, DateTime localNow) {
  final daysAgo = _daysAgo(localT, localNow);
  if (daysAgo <= 0) return _DayBucket.today;
  if (daysAgo == 1) return _DayBucket.yesterday;
  // Exactly 7 days ago is the same weekday as today, so the weekday bucket
  // stops at 6; day 7+ falls through to the date.
  if (daysAgo <= 6) return _DayBucket.weekday;
  return localT.year == localNow.year ? _DayBucket.thisYear : _DayBucket.older;
}

/// Muted caption under a message bubble. Today shows just the time (the day
/// divider carries the day); older buckets stay self-describing.
///
/// - same day → `2:14 PM`
/// - previous day → `Yesterday · 4:12 PM`
/// - 2–6 days ago → `Mon · 9:03 AM`
/// - earlier this year → `Mar 3 · 9:03 AM`
/// - older → `Mar 3, 2025 · 9:03 AM`
String formatMessageCaption(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final clock = formatClock12(local);
  return switch (_bucketFor(local, localNow)) {
    _DayBucket.today => clock,
    _DayBucket.yesterday => 'Yesterday · $clock',
    _DayBucket.weekday => '${weekdayAbbrev(local)} · $clock',
    _DayBucket.thisYear => '${monthAbbrev(local)} ${local.day} · $clock',
    _DayBucket.older =>
      '${monthAbbrev(local)} ${local.day}, ${local.year} · $clock',
  };
}

/// Centered day-divider label. Uses full names (the divider is the prominent
/// marker) and carries the date on the 2–6-day bucket so the literal date is
/// visible once per group.
///
/// - today → `Today`
/// - yesterday → `Yesterday`
/// - 2–6 days ago → `Monday, June 23`
/// - earlier this year → `March 3`
/// - older → `March 3, 2025`
String formatDayDivider(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final weekday = weekdayNames[local.weekday - 1];
  final month = monthNames[local.month - 1];
  return switch (_bucketFor(local, localNow)) {
    _DayBucket.today => 'Today',
    _DayBucket.yesterday => 'Yesterday',
    _DayBucket.weekday => '$weekday, $month ${local.day}',
    _DayBucket.thisYear => '$month ${local.day}',
    _DayBucket.older => '$month ${local.day}, ${local.year}',
  };
}
