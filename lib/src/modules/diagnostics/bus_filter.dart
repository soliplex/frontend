import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadKey;

import 'bus_inspector.dart';
import 'snapshot_diff.dart';

/// Recognised key prefixes in the filter mini-language.
///
/// Tokens NOT prefixed by one of these are treated as bare text and
/// must match at least one of the matchable fields (thread short id,
/// room id, tag, or any changed path).
const Set<String> kFilterKeys = {
  'thread',
  'room',
  'server',
  'tag',
  'path',
  'kind',
};

/// Row kinds the filter recognises via `kind:`. Bus commits are tagged
/// `bus`; recorded raw AG-UI events are tagged `event`.
enum RowKind { bus, event }

/// Parsed filter applied to inspector rows; each non-null field must
/// match for the row to pass. Bare terms must each match somewhere.
///
/// The same filter applies to both bus commits and event records;
/// fields not relevant to a given row kind (e.g. `pathSubstr` on an
/// event record) are skipped via the kind-aware match methods below.
@immutable
class BusFilter {
  const BusFilter({
    this.threadSubstr,
    this.roomSubstr,
    this.serverSubstr,
    this.tagPattern,
    this.pathSubstr,
    this.kind,
    this.bareTerms = const [],
  });

  static const BusFilter empty = BusFilter();

  /// Substring match against `ThreadKey.threadId` (case-insensitive).
  final String? threadSubstr;

  /// Substring match against `ThreadKey.roomId` (case-insensitive).
  final String? roomSubstr;

  /// Substring match against `ThreadKey.serverId` (case-insensitive).
  final String? serverSubstr;

  /// Tag matcher — exact value, or prefix when input ends in `*`
  /// (e.g. `agui.*`).
  final TagPattern? tagPattern;

  /// Substring match against any changed path in the diff
  /// (case-insensitive). Only applies to bus rows.
  final String? pathSubstr;

  /// Row kind filter (`bus` or `event`). When set, rows of the other
  /// kind are filtered out.
  final RowKind? kind;

  /// Bare (unprefixed) tokens. Each one must match at least one of:
  /// thread short id, room id, server id, tag, or (for bus rows) any
  /// changed path.
  final List<String> bareTerms;

  bool get isEmpty =>
      threadSubstr == null &&
      roomSubstr == null &&
      serverSubstr == null &&
      tagPattern == null &&
      pathSubstr == null &&
      kind == null &&
      bareTerms.isEmpty;

  bool matchesBus(BusEvent event, SnapshotDiff diff) {
    if (kind != null && kind != RowKind.bus) return false;
    if (threadSubstr != null &&
        !_substr(event.threadKey.threadId, threadSubstr!)) {
      return false;
    }
    if (roomSubstr != null && !_substr(event.threadKey.roomId, roomSubstr!)) {
      return false;
    }
    if (serverSubstr != null &&
        !_substr(event.threadKey.serverId, serverSubstr!)) {
      return false;
    }
    if (tagPattern != null && !tagPattern!.matches(event.tag)) {
      return false;
    }
    if (pathSubstr != null && !_anyPathContains(diff, pathSubstr!)) {
      return false;
    }
    for (final term in bareTerms) {
      if (!_anyBusFieldContains(event, diff, term)) return false;
    }
    return true;
  }

  bool matchesEvent(EventRecord record) {
    if (kind != null && kind != RowKind.event) return false;
    if (threadSubstr != null &&
        !_substr(record.threadKey.threadId, threadSubstr!)) {
      return false;
    }
    if (roomSubstr != null && !_substr(record.threadKey.roomId, roomSubstr!)) {
      return false;
    }
    if (serverSubstr != null &&
        !_substr(record.threadKey.serverId, serverSubstr!)) {
      return false;
    }
    if (tagPattern != null && !tagPattern!.matches(record.tag)) {
      return false;
    }
    // pathSubstr does not apply to event records — skip.
    for (final term in bareTerms) {
      if (!_anyEventFieldContains(record, term)) return false;
    }
    return true;
  }

  /// Backwards-compatible alias for [matchesBus].
  bool matches(BusEvent event, SnapshotDiff diff) => matchesBus(event, diff);
}

/// A tag predicate: either an exact string or a prefix glob (input
/// ending in `*`, where the `*` is interpreted as a wildcard).
@immutable
class TagPattern {
  const TagPattern.exact(this.value) : isPrefix = false;
  const TagPattern.prefix(this.value) : isPrefix = true;

  final String value;
  final bool isPrefix;

  bool matches(String? tag) {
    if (tag == null) return false;
    if (isPrefix) return tag.toLowerCase().startsWith(value.toLowerCase());
    return tag.toLowerCase() == value.toLowerCase();
  }
}

/// Parses a filter string into a [BusFilter]. Whitespace separates
/// tokens; tokens of the form `key:value` are recognised when `key` is
/// in [kFilterKeys] (case-insensitive). Empty input → [BusFilter.empty].
/// Later occurrences of the same prefix override earlier ones.
BusFilter parseBusFilter(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return BusFilter.empty;

  String? thread;
  String? room;
  String? server;
  TagPattern? tag;
  String? path;
  RowKind? kind;
  final bare = <String>[];

  for (final raw in trimmed.split(RegExp(r'\s+'))) {
    if (raw.isEmpty) continue;
    final colon = raw.indexOf(':');
    if (colon > 0 && colon < raw.length - 1) {
      final key = raw.substring(0, colon).toLowerCase();
      final value = raw.substring(colon + 1);
      if (kFilterKeys.contains(key)) {
        switch (key) {
          case 'thread':
            thread = value;
          case 'room':
            room = value;
          case 'server':
            server = value;
          case 'tag':
            tag = value.endsWith('*')
                ? TagPattern.prefix(value.substring(0, value.length - 1))
                : TagPattern.exact(value);
          case 'path':
            path = value;
          case 'kind':
            switch (value.toLowerCase()) {
              case 'bus':
                kind = RowKind.bus;
              case 'event':
                kind = RowKind.event;
              default:
                bare.add(raw);
            }
        }
        continue;
      }
    }
    bare.add(raw);
  }

  return BusFilter(
    threadSubstr: thread,
    roomSubstr: room,
    serverSubstr: server,
    tagPattern: tag,
    pathSubstr: path,
    kind: kind,
    bareTerms: List.unmodifiable(bare),
  );
}

/// Identify the "current token" the user is editing at [cursor] inside
/// [text]. Used by the search field to drive autocomplete suggestions.
/// Returns `null` if the cursor is not inside any token.
({String token, int start, int end})? currentTokenAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  // Walk left from cursor while non-whitespace.
  var start = cursor;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  // Walk right from cursor while non-whitespace.
  var end = cursor;
  while (end < text.length && !_isSpace(text.codeUnitAt(end))) {
    end++;
  }
  if (start == end) return null;
  return (token: text.substring(start, end), start: start, end: end);
}

/// Build autocomplete suggestions for the token at [cursor] in [text]
/// against the values present in [rows].
///
/// Behaviour:
/// - `key:` (empty value) → all known values for that key
/// - `key:partial` → values matching `partial` substring
/// - bare partial → matching key names (`thread`, `room`, …) for the
///   user to expand
List<String> suggestionsFor({
  required String text,
  required int cursor,
  required Iterable<BusEvent> events,
  Iterable<EventRecord> records = const [],
}) {
  final at = currentTokenAt(text, cursor);
  if (at == null) {
    return kFilterKeys.map((k) => '$k:').toList();
  }
  final tok = at.token;
  final colon = tok.indexOf(':');
  if (colon < 0) {
    final lower = tok.toLowerCase();
    return [
      for (final k in kFilterKeys)
        if (k.startsWith(lower)) '$k:',
    ];
  }
  final key = tok.substring(0, colon).toLowerCase();
  final partial = tok.substring(colon + 1).toLowerCase();
  if (!kFilterKeys.contains(key)) return const [];
  final values = _valuesForKey(key, events, records);
  return [
    for (final v in values)
      if (partial.isEmpty || v.toLowerCase().contains(partial)) '$key:$v',
  ];
}

Set<String> _valuesForKey(
  String key,
  Iterable<BusEvent> events, [
  Iterable<EventRecord> records = const [],
]) {
  final out = <String>{};
  for (final e in events) {
    switch (key) {
      case 'thread':
        out.add(_threadShort(e.threadKey));
      case 'room':
        out.add(e.threadKey.roomId);
      case 'server':
        out.add(e.threadKey.serverId);
      case 'tag':
        if (e.tag != null) out.add(e.tag!);
      case 'kind':
        out.add('bus');
    }
  }
  for (final r in records) {
    switch (key) {
      case 'thread':
        out.add(_threadShort(r.threadKey));
      case 'room':
        out.add(r.threadKey.roomId);
      case 'server':
        out.add(r.threadKey.serverId);
      case 'tag':
        out.add(r.tag);
      case 'kind':
        out.add('event');
    }
  }
  return out;
}

String _threadShort(ThreadKey key) {
  final tid = key.threadId;
  return tid.length <= 6 ? tid : tid.substring(tid.length - 6);
}

bool _substr(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());

bool _anyPathContains(SnapshotDiff diff, String needle) {
  bool match(String s) => s.toLowerCase().contains(needle.toLowerCase());
  return diff.added.any((c) => match(c.path)) ||
      diff.removed.any((c) => match(c.path)) ||
      diff.replaced.any((c) => match(c.path));
}

bool _anyBusFieldContains(BusEvent event, SnapshotDiff diff, String term) {
  final t = term.toLowerCase();
  if (_threadShort(event.threadKey).toLowerCase().contains(t)) return true;
  if (event.threadKey.roomId.toLowerCase().contains(t)) return true;
  if (event.threadKey.serverId.toLowerCase().contains(t)) return true;
  if ((event.tag ?? '').toLowerCase().contains(t)) return true;
  return _anyPathContains(diff, term);
}

bool _anyEventFieldContains(EventRecord record, String term) {
  final t = term.toLowerCase();
  if (_threadShort(record.threadKey).toLowerCase().contains(t)) return true;
  if (record.threadKey.roomId.toLowerCase().contains(t)) return true;
  if (record.threadKey.serverId.toLowerCase().contains(t)) return true;
  if (record.tag.toLowerCase().contains(t)) return true;
  return false;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A;
