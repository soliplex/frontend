/// Formatting + bucketing for a room's most-recent-thread activity timestamp.
///
/// The lobby shows this both as a per-card relative label ("3h ago") and, when
/// sorting by recent activity, as date-bucketed section headers ("Today",
/// "Yesterday", ...) in the manner of an LLM chat history.
///
/// The label and the buckets use different recency models on purpose:
/// [formatRelativeActivity] measures elapsed duration ("2d ago"), while
/// [bucketFor] uses calendar-day deltas. So near a day boundary a room can read
/// "23h ago" on its card yet sit under a "Yesterday" header (23h elapsed but
/// the calendar day rolled over), and a timestamp old enough to show a numeric
/// date (>7 days elapsed) always buckets under "This month"/"Older", never
/// "This week" — expected, not a bug.
library;

/// Short relative label for [time], e.g. "Just now", "5m ago", "3h ago",
/// "2d ago", falling back to a numeric date for anything older than a week.
String formatRelativeActivity(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  // Backend timestamps are UTC; render the date in the viewer's zone.
  final local = time.toLocal();
  return '${local.month}/${local.day}/${local.year}';
}

/// Recency buckets used to group rooms under section headers. Ordered from
/// most to least recent; [none] (no known timestamp) always sorts last.
enum ActivityBucket {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  thisMonth('This month'),
  older('Older'),
  none('No activity');

  const ActivityBucket(this.label);

  /// Human-readable section header.
  final String label;
}

/// Buckets [time] relative to [now] (defaults to the current time). A `null`
/// timestamp — no threads, not yet fetched, or a failed lookup — maps to
/// [ActivityBucket.none].
ActivityBucket bucketFor(DateTime? time, {DateTime? now}) {
  if (time == null) return ActivityBucket.none;
  // Buckets are calendar days in the viewer's zone. Thread timestamps arrive in
  // UTC, so read each side's day in local time. The two days are then pinned to
  // UTC midnight before differencing: that keeps the gap an exact 24h multiple,
  // so a DST transition (a 23h or 25h local day) can't shift the day count.
  final reference = (now ?? DateTime.now()).toLocal();
  final local = time.toLocal();
  final today = DateTime.utc(reference.year, reference.month, reference.day);
  final thatDay = DateTime.utc(local.year, local.month, local.day);
  final dayDelta = today.difference(thatDay).inDays;
  if (dayDelta <= 0) return ActivityBucket.today;
  if (dayDelta == 1) return ActivityBucket.yesterday;
  if (dayDelta < 7) return ActivityBucket.thisWeek;
  if (dayDelta < 30) return ActivityBucket.thisMonth;
  return ActivityBucket.older;
}
