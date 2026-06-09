/// Formatting + bucketing for a room's most-recent-thread activity timestamp.
///
/// The lobby shows this both as a per-card relative label ("3h ago") and, when
/// sorting by recent activity, as date-bucketed section headers ("Today",
/// "Yesterday", ...) in the manner of an LLM chat history.
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
  return '${time.month}/${time.day}/${time.year}';
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
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final thatDay = DateTime(time.year, time.month, time.day);
  final dayDelta = today.difference(thatDay).inDays;
  if (dayDelta <= 0) return ActivityBucket.today;
  if (dayDelta == 1) return ActivityBucket.yesterday;
  if (dayDelta < 7) return ActivityBucket.thisWeek;
  if (dayDelta < 30) return ActivityBucket.thisMonth;
  return ActivityBucket.older;
}
