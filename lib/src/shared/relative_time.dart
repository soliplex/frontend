import 'local_time_format.dart';

/// Short relative label for [time], e.g. "Just now", "5m ago", "3h ago",
/// "2d ago", falling back to a numeric date (M/D/YYYY) for anything older than
/// a week or a minute or more ahead of the clock.
///
/// Backend timestamps arrive as UTC instants, so [time] is converted to the
/// viewer's zone up front: every calendar field read below is local, and the
/// numeric-date fallback shows the viewer's date rather than the UTC date.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  return switch (_ago(local, now ?? DateTime.now())) {
    null => '${local.month}/${local.day}/${local.year}',
    (count: 0, unit: _) => 'Just now',
    (:final count, :final unit) => '$count${unit[0]} ago',
  };
}

/// [formatRelativeTime] for a screen reader: "just now", "5 minutes ago",
/// "1 day ago", then the date in words, "June 2, 2026".
String spokenRelativeTime(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  return switch (_ago(local, now ?? DateTime.now())) {
    null => '${monthNames[local.month - 1]} ${local.day}, ${local.year}',
    (count: 0, unit: _) => 'just now',
    (:final count, :final unit) => '$count $unit${count == 1 ? '' : 's'} ago',
  };
}

/// How long before [now] [local] was, in the largest whole unit under a week;
/// a count of zero is under a minute either way. Null from a week on, and for
/// a time a minute or more ahead, as clock skew or a file stamped in the
/// future gives: "Just now" would hide it, and pin a folder that shows its
/// newest file there.
({int count, String unit})? _ago(DateTime local, DateTime now) {
  final diff = now.difference(local);
  if (diff.inMinutes <= -1) return null;
  if (diff.inMinutes < 1) return (count: 0, unit: 'minute');
  if (diff.inMinutes < 60) return (count: diff.inMinutes, unit: 'minute');
  if (diff.inHours < 24) return (count: diff.inHours, unit: 'hour');
  if (diff.inDays < 7) return (count: diff.inDays, unit: 'day');
  return null;
}
