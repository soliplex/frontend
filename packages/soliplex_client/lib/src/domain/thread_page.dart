import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/thread_info.dart';

/// One page of a user's threads, drawn from every room they can see.
///
/// The backend orders the threads by their own last activity, most recent
/// first, and pages by an opaque [nextCursor] rather than an offset, so a
/// thread started between two requests doesn't shift the rest of the
/// listing by a row.
///
/// The cursor marks a position in that order, so the listing drifts while
/// it is paged: a thread that gains activity after its page was fetched
/// moves above the cursor, and later pages skip it until the first page
/// is fetched again.
@immutable
class ThreadPage {
  /// Creates a page of threads.
  const ThreadPage({required this.threads, this.nextCursor});

  /// The threads on this page, in display order.
  final List<ThreadInfo> threads;

  /// The token that fetches the page after this one, or `null` when this
  /// page is the last. Opaque: pass it back unchanged.
  final String? nextCursor;

  /// Whether another page remains after this one.
  bool get hasMore => nextCursor != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThreadPage &&
        other.nextCursor == nextCursor &&
        _sameThreads(other.threads);
  }

  bool _sameThreads(List<ThreadInfo> other) {
    if (other.length != threads.length) return false;
    for (var i = 0; i < threads.length; i++) {
      if (other[i] != threads[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(nextCursor, Object.hashAll(threads));

  @override
  String toString() =>
      'ThreadPage(threads: ${threads.length}, hasMore: $hasMore)';
}
