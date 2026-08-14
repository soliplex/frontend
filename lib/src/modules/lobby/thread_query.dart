import 'package:flutter/foundation.dart';

/// A thread search split into its two independent halves.
///
/// The search box takes both at once — `Osprey Manual @manuals` — and
/// either alone. They are separate filters server-side (name contains,
/// labels any-of), so they are kept separate here rather than being
/// flattened into one string.
@immutable
class ThreadQuery {
  /// Creates a parsed query.
  const ThreadQuery({required this.text, required this.labelNames});

  /// An empty query, matching everything.
  static const empty = ThreadQuery(text: '', labelNames: []);

  /// The free text, with every `@label` token removed and the
  /// surrounding whitespace collapsed.
  final String text;

  /// The label names typed as `@name`, in the order given, without
  /// their leading `@` and lower-cased.
  ///
  /// Lower-cased because label names ignore case, so `@Urgent` and
  /// `@urgent` must resolve to the same label rather than one of them
  /// silently matching nothing.
  final List<String> labelNames;

  /// Whether this query filters anything at all.
  bool get isEmpty => text.isEmpty && labelNames.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ThreadQuery) return false;
    if (other.text != text) return false;
    if (other.labelNames.length != labelNames.length) return false;
    for (var i = 0; i < labelNames.length; i++) {
      if (other.labelNames[i] != labelNames[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(labelNames));

  @override
  String toString() => 'ThreadQuery(text: "$text", labels: $labelNames)';
}

/// Characters that end an `@label` token.
///
/// A label name runs to the next space or punctuation, so
/// `@urgent, @manuals` and `@urgent。` both terminate cleanly rather
/// than swallowing the separator into the name.
final RegExp _labelToken = RegExp(r'@([^\s,;]+)');

/// Splits a raw search string into free text and `@label` tokens.
///
/// Both halves are optional and independent:
///
/// ```text
/// "Osprey Manual"             -> text only
/// "@manuals @v22osprey"       -> labels only
/// "Osprey @manuals"           -> both
/// ```
///
/// A bare `@` is not a token — it is what the user has typed so far
/// while the autocomplete is open — and is left in the text rather than
/// producing an empty label name that would match nothing.
///
/// Duplicate labels collapse: `@urgent @urgent` filters once. The
/// server treats the list as "any of", so a repeat would be a no-op
/// anyway, but sending it would make the request misrepresent the
/// question.
ThreadQuery parseThreadQuery(String raw) {
  final labelNames = <String>[];
  final seen = <String>{};

  final text = raw.replaceAllMapped(_labelToken, (match) {
    final name = match.group(1)!.toLowerCase();
    if (seen.add(name)) labelNames.add(name);
    // Replaced with a space, not with nothing: removing the token
    // outright would weld its neighbours together, turning
    // "Osprey @manuals Manual" into "Osprey Manual" with no gap.
    return ' ';
  });

  return ThreadQuery(
    text: _collapseWhitespace(text),
    labelNames: List.unmodifiable(labelNames),
  );
}

/// The in-progress `@` token at [cursor], or null when there is none.
///
/// Drives the autocomplete: it is the text between the last unescaped
/// `@` before the cursor and the cursor itself, provided nothing
/// separates them. Returns an empty string for a bare `@`, which is a
/// real state — the user has opened the menu but typed no name yet, and
/// the menu should show everything.
///
/// Returns null once the token is finished (whitespace or punctuation
/// follows the `@`), which is what closes the menu.
String? activeLabelToken(String raw, int cursor) {
  if (cursor < 0 || cursor > raw.length) return null;

  final before = raw.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;

  final token = before.substring(at + 1);
  // Any separator inside means the token already ended; what follows is
  // ordinary text, not a name still being typed.
  if (token.contains(RegExp(r'[\s,;]'))) return null;

  return token.toLowerCase();
}

/// [raw] with the in-progress `@` token at [cursor] replaced by [name].
///
/// Returns the new text and where the cursor should land — after the
/// trailing space, so the user can keep typing without reaching for it.
/// Returns null when there is no token to complete.
({String text, int cursor})? completeLabelToken(
  String raw,
  int cursor,
  String name,
) {
  if (activeLabelToken(raw, cursor) == null) return null;

  final at = raw.substring(0, cursor).lastIndexOf('@');
  final replacement = '@$name ';
  final text = raw.replaceRange(at, cursor, replacement);

  return (text: text, cursor: at + replacement.length);
}

String _collapseWhitespace(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
