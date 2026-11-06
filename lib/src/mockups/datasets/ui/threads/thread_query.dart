import 'package:flutter/foundation.dart';

export '../../../../modules/lobby/thread_query.dart' show noLabelToken;

// MOCKUP: a copy of the lobby's `thread_query.dart` that also reads `in:room`
// tokens, so a search can name the rooms it looks in. `in:none` names the
// conversations outside every room.

/// The two kinds of token the search box completes.
enum TokenKind {
  label('@'),
  room('in:');

  const TokenKind(this.prefix);

  final String prefix;
}

/// What `in:none` reads as: no room at all.
const noRoomToken = 'none';

/// A thread search split into free text, `@label` and `in:room` tokens.
@immutable
class ThreadQuery {
  const ThreadQuery({
    required this.text,
    required this.labelNames,
    this.roomNames = const [],
  });

  static const empty = ThreadQuery(text: '', labelNames: []);

  final String text;

  /// The `@label` names, lower-cased, without the `@`.
  final List<String> labelNames;

  /// The `in:room` names, lower-cased, without the `in:`; [noRoomToken] for
  /// conversations outside rooms.
  final List<String> roomNames;

  List<String> namesOf(TokenKind kind) =>
      kind == TokenKind.label ? labelNames : roomNames;

  @override
  bool operator ==(Object other) =>
      other is ThreadQuery &&
      other.text == text &&
      listEquals(other.labelNames, labelNames) &&
      listEquals(other.roomNames, roomNames);

  @override
  int get hashCode =>
      Object.hash(text, Object.hashAll(labelNames), Object.hashAll(roomNames));
}

/// `@name`, `in:name`, or either with a quoted `"name with spaces"`. `in:`
/// counts only at the start of a word, so `login:x` stays text.
final RegExp _token =
    RegExp(r'(@|(?<!\S)in:)(?:"([^"]*)"|([^\s,;"]+))', caseSensitive: false);

/// Where a token could start: the last `@` or word-initial `in:`.
final RegExp _tokenStart = RegExp(r'@|(?<!\S)in:', caseSensitive: false);

/// [name] as [kind]'s token, quoted when it would not survive a re-read.
String formatToken(TokenKind kind, String name) =>
    RegExp(r'[\s,;"]').hasMatch(name)
        ? '${kind.prefix}"$name"'
        : '${kind.prefix}$name';

ThreadQuery parseThreadQuery(String raw) {
  final names = {for (final kind in TokenKind.values) kind: <String>[]};

  final text = raw.replaceAllMapped(_token, (match) {
    final kind = match.group(1) == '@' ? TokenKind.label : TokenKind.room;
    final name = (match.group(2) ?? match.group(3)!).toLowerCase();
    if (name.isNotEmpty && !names[kind]!.contains(name)) {
      names[kind]!.add(name);
    }
    return ' ';
  });

  return ThreadQuery(
    text: text.trim().replaceAll(RegExp(r'\s+'), ' '),
    labelNames: List.unmodifiable(names[TokenKind.label]!),
    roomNames: List.unmodifiable(names[TokenKind.room]!),
  );
}

/// The token being typed at [cursor]: its kind, where it starts, and the
/// lower-cased name so far (empty right after the prefix). Null when the
/// cursor is not inside one.
({TokenKind kind, int start, String partial})? activeToken(
  String raw,
  int cursor,
) {
  if (cursor < 0 || cursor > raw.length) return null;
  final before = raw.substring(0, cursor);
  final match = _tokenStart.allMatches(before).lastOrNull;
  if (match == null) return null;

  final kind = match.group(0) == '@' ? TokenKind.label : TokenKind.room;
  final token = before.substring(match.end);
  if (token.startsWith('"')) {
    final inner = token.substring(1);
    if (inner.contains('"')) return null;
    return (kind: kind, start: match.start, partial: inner.toLowerCase());
  }
  if (token.contains(RegExp(r'[\s,;]'))) return null;
  return (kind: kind, start: match.start, partial: token.toLowerCase());
}

/// [raw] with the token at [cursor] replaced by [name]'s, and where the
/// cursor lands after it.
({String text, int cursor})? completeToken(
  String raw,
  int cursor,
  String name,
) {
  final active = activeToken(raw, cursor);
  if (active == null) return null;
  final replacement = '${formatToken(active.kind, name)} ';
  return (
    text: raw.replaceRange(active.start, cursor, replacement),
    cursor: active.start + replacement.length,
  );
}
