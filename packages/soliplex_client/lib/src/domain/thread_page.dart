import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/thread_info.dart';

/// One page of a user's threads, drawn from every room they can see.
///
/// The backend orders the threads by their own last activity, most recent
/// first, and pages by an opaque [nextCursor] rather than an offset, so a
/// thread started or reordered between two requests never shifts the rest
/// of the listing.
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
