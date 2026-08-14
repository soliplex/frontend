import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/thread_info.dart';

/// One page of a user's threads, drawn from every room they can see.
///
/// The backend orders the threads so that each room's threads are
/// contiguous — rooms by their latest activity, threads alphabetically
/// within a room — which is what lets a client emit a section divider
/// whenever [ThreadInfo.roomId] changes rather than regrouping itself.
@immutable
class ThreadPage {
  /// Creates a page of threads.
  const ThreadPage({
    required this.threads,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// The threads on this page, in display order.
  final List<ThreadInfo> threads;

  /// How many threads match in total, across every page.
  final int total;

  /// The page size that was requested.
  final int limit;

  /// How many threads were skipped before this page.
  final int offset;

  /// Whether another page remains after this one.
  ///
  /// Derived from [total] rather than from a short page, so a client can
  /// tell there is nothing more without spending a request to find out.
  bool get hasMore => offset + threads.length < total;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThreadPage &&
        other.total == total &&
        other.limit == limit &&
        other.offset == offset &&
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
  int get hashCode => Object.hash(
        total,
        limit,
        offset,
        Object.hashAll(threads),
      );

  @override
  String toString() => 'ThreadPage(threads: ${threads.length}, total: $total, '
      'limit: $limit, offset: $offset)';
}
