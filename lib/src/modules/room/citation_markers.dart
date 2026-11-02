import 'package:soliplex_agent/soliplex_agent.dart';

/// The scheme of the link a citation marker becomes, carrying the cited
/// source's position in its answer's source list.
const citationLinkScheme = 'soliplex-citation';

/// The number a citation is shown under: the backend's `index`, which holds
/// across the conversation, or its place in the list when the capability
/// reports none.
///
/// Shared by the source list's badge and the marker in the answer's text, so
/// the two cannot disagree about which number names a source.
int citationBadgeNumber(SourceReference ref, int position) =>
    ref.index ?? position + 1;

/// The chunk ids a citation answers to: its own, and every id it merged. The
/// model is shown each of them, so it can name the citation by any one.
Iterable<String> _keysOf(SourceReference ref) => {ref.chunkId, ...ref.chunkIds};

/// Every chunk id cited anywhere in a thread, mapped to its number.
///
/// Only citations carrying a backend `index` are taken: that number is assigned
/// once per chunk id and kept for the conversation, so it names the same source
/// whichever turn's text uses it. A positional fallback means nothing outside
/// the list it was counted in.
Map<String, int> threadCitationNumbers(
  Iterable<List<SourceReference>> turns,
) {
  final numbers = <String, int>{};
  for (final refs in turns) {
    for (final ref in refs) {
      final index = ref.index;
      if (index == null) continue;
      for (final key in _keysOf(ref)) {
        numbers.putIfAbsent(key, () => index);
      }
    }
  }
  return numbers;
}

/// The source-list position a citation link's [href] points at, or null when
/// [href] is not a citation link.
int? citationPositionFromHref(String href) {
  const prefix = '$citationLinkScheme:';
  if (!href.startsWith(prefix)) return null;
  return int.tryParse(href.substring(prefix.length));
}

/// A bracketed group the model may have cited with: `[a]`, `[a, b]`, `[a; b]`.
/// One directly followed by `(` is a markdown link's text, and is left alone.
final _marker = RegExp(r'\[([^\[\]\n]+)\](?!\()');

/// Separators between the ids of one bracketed group.
final _separator = RegExp(r'[,;\s]+');

/// An inline code span: a run of backticks, its content, and a closing run of
/// the same length.
final _codeSpan = RegExp(r'(`+)[\s\S]*?(?<!`)\1(?!`)');

/// The opening or closing line of a fenced code block.
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// `[n]` written as markdown that renders as exactly that.
///
/// Entities rather than backslash escapes: `\[…\]` is display-math to the
/// renderer's LaTeX syntax, which would eat the brackets. Entities are decoded
/// after links are parsed, so `[2][3]` cannot read as a reference link either.
String _bracketed(int number) => '&#91;$number&#93;';

/// [text] with each bracketed group of cited chunk ids replaced by the
/// numbers the source list shows for them.
///
/// [own] is this answer's source list. A group naming a source in it becomes a
/// link to that source's row when [linkify] is set. [thread] is
/// [threadCitationNumbers] over the whole thread: a source this answer did not
/// cite again, cited in an earlier turn, is shown under its number without a
/// link, its row being in another answer's list.
///
/// A group is rewritten only when every id in it is known, so prose that
/// happens to sit in brackets is left alone, as is an id the model damaged
/// while copying it. Code blocks and code spans are never touched.
///
/// With [linkify] unset the result is plain text, for the clipboard.
String labelCitationMarkers(
  String text, {
  required List<SourceReference> own,
  required Map<String, int> thread,
  required bool linkify,
}) {
  if ((own.isEmpty && thread.isEmpty) || !text.contains('[')) return text;

  final positions = <String, int>{};
  for (var position = 0; position < own.length; position++) {
    for (final key in _keysOf(own[position])) {
      positions.putIfAbsent(key, () => position);
    }
  }

  String label(Match match) {
    final ids = match[1]!.split(_separator).where((id) => id.isNotEmpty);
    final labels = <int, String>{};
    for (final id in ids) {
      final position = positions[id];
      if (position != null) {
        final number = citationBadgeNumber(own[position], position);
        labels.putIfAbsent(
          number,
          () => linkify
              ? '[${_bracketed(number)}]($citationLinkScheme:$position)'
              : '[$number]',
        );
        continue;
      }
      final number = thread[id];
      if (number == null) return match[0]!;
      labels.putIfAbsent(
        number,
        () => linkify ? _bracketed(number) : '[$number]',
      );
    }
    return labels.isEmpty ? match[0]! : labels.values.join();
  }

  String prose(String segment) {
    final out = StringBuffer();
    var start = 0;
    for (final span in _codeSpan.allMatches(segment)) {
      out
        ..write(segment.substring(start, span.start).replaceAllMapped(
              _marker,
              label,
            ))
        ..write(span[0]);
      start = span.end;
    }
    out.write(segment.substring(start).replaceAllMapped(_marker, label));
    return out.toString();
  }

  final out = <String>[];
  final paragraph = <String>[];
  String? fence;
  void flush() {
    if (paragraph.isEmpty) return;
    out.add(prose(paragraph.join('\n')));
    paragraph.clear();
  }

  for (final line in text.split('\n')) {
    final opener = _fence.firstMatch(line)?[1];
    if (fence == null) {
      if (opener != null) {
        flush();
        fence = opener;
        out.add(line);
      } else {
        paragraph.add(line);
      }
    } else {
      out.add(line);
      if (opener != null &&
          opener[0] == fence[0] &&
          opener.length >= fence.length) {
        fence = null;
      }
    }
  }
  flush();
  return out.join('\n');
}
