/// Short relative label for [time], e.g. "Just now", "5m ago", "3h ago",
/// "2d ago", falling back to a numeric date (M/D/YYYY) for anything older than
/// a week.
///
/// Backend timestamps arrive as UTC instants, so [time] is converted to the
/// viewer's zone up front: every calendar field read below is local, and the
/// numeric-date fallback shows the viewer's date rather than the UTC date.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final reference = now ?? DateTime.now();
  final diff = reference.difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${local.month}/${local.day}/${local.year}';
}
