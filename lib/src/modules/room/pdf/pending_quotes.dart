import 'package:signals_flutter/signals_flutter.dart';

import '../../auth/server_entry.dart';
import '../per_server_cache.dart';
import 'pdf_quote.dart';

/// The quotes waiting to go with a room's next message, per thread.
///
/// Kept per thread, as document filters are: a passage quoted in one
/// conversation must not ride along with a message in another, and coming
/// back to a thread shows what was waiting there. `null` is the room's
/// welcome screen, before a thread exists.
class RoomQuotes {
  final _byThread = signal<Map<String?, List<PdfQuote>>>(const {});

  /// Every thread's waiting quotes, for a widget to watch.
  ReadonlySignal<Map<String?, List<PdfQuote>>> get all => _byThread;

  /// The quotes waiting in [threadId], oldest first. Reading it inside an
  /// effect or a `Watch` subscribes the reader to changes.
  List<PdfQuote> watch(String? threadId) =>
      _byThread.value[threadId] ?? const [];

  /// [watch], without subscribing.
  List<PdfQuote> peek(String? threadId) =>
      _byThread.peek()[threadId] ?? const [];

  /// Adds [quote] unless the same passage is already waiting.
  void add(String? threadId, PdfQuote quote) {
    final current = peek(threadId);
    if (current.contains(quote)) return;
    _set(threadId, [...current, quote]);
  }

  /// Puts [quotes] back ahead of whatever is waiting — a send that failed
  /// returns what it took.
  void restore(String? threadId, List<PdfQuote> quotes) {
    if (quotes.isEmpty) return;
    final current = peek(threadId);
    _set(threadId, [
      ...quotes,
      ...current.where((quote) => !quotes.contains(quote)),
    ]);
  }

  void remove(String? threadId, PdfQuote quote) =>
      _set(threadId, [...peek(threadId)]..remove(quote));

  /// The quotes waiting in [threadId], leaving none — for a send.
  List<PdfQuote> take(String? threadId) {
    final taken = peek(threadId);
    if (taken.isNotEmpty) _set(threadId, const []);
    return taken;
  }

  /// Drops the quotes of a deleted thread.
  void clearThread(String threadId) => _set(threadId, const []);

  /// Moves the welcome screen's quotes to [threadId], when the room goes from
  /// no thread to one — normally the thread the first send creates.
  void migrateToThread(String threadId) {
    final pending = peek(null);
    if (pending.isEmpty) return;
    final next = {..._byThread.peek()}..remove(null);
    next[threadId] = pending;
    _byThread.value = next;
  }

  void _set(String? threadId, List<PdfQuote> quotes) {
    final next = {..._byThread.peek()};
    if (quotes.isEmpty) {
      if (next.remove(threadId) == null) return;
    } else {
      next[threadId] = List.unmodifiable(quotes);
    }
    _byThread.value = next;
  }

  void dispose() => _byThread.dispose();
}

/// Each room's [RoomQuotes], per server entry.
///
/// The room module keeps it, not the room screen, so quotes outlive a visit
/// to another room. Quotes are document text, so they go when their server
/// is removed (through [PerServerCache]) and when a different user signs in
/// on it ([evictServer], from `UserSwitchTeardown`).
class PendingQuotesRegistry {
  PendingQuotesRegistry({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
  }) : _quotes = PerServerCache(
          servers: servers,
          disposeValue: (quotes) => quotes.dispose(),
        );

  final PerServerCache<String, RoomQuotes> _quotes;

  /// The quotes of [roomId] on [entry]. Throws [StateError] once disposed.
  RoomQuotes quotesFor({required ServerEntry entry, required String roomId}) =>
      _quotes.putIfAbsent(entry, roomId, RoomQuotes.new);

  /// Drops every room's quotes on [serverId].
  void evictServer(String serverId) => _quotes.evictServer(serverId);

  void dispose() => _quotes.dispose();
}
