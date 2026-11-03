import 'package:soliplex_agent/soliplex_agent.dart';

/// The number a citation is shown under: the backend's `index`, or its place
/// in the list when the capability reports none.
///
/// Shared by the source list's badge and the marker in the answer's text, so
/// the two cannot disagree about which number names a source.
int citationBadgeNumber(SourceReference ref, int position) =>
    ref.index ?? position + 1;

/// The chunk ids a citation answers to: its own, and every id merged into it.
/// A marker naming any of them is labelled with the citation's number.
Iterable<String> _keysOf(SourceReference ref) => {ref.chunkId, ...ref.chunkIds};

/// Every chunk id cited anywhere in a thread by a citation carrying a backend
/// `index`, mapped to that index. When two citations claim one id, the first
/// met keeps it.
///
/// Only citations carrying a backend `index` are taken: the backend keeps each
/// cited chunk's citation, `index` included, in a `citation_index` that spans
/// the conversation, so the number names the same source whichever turn's text
/// uses it. A positional fallback means nothing outside the list it was
/// counted in.
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

/// A bracketed group the model may have cited with: `[a]`, `[a, b]`, `[a; b]`.
/// One directly followed by `(` is a markdown link's text, and is left alone.
final _marker = RegExp(r'\[([^\[\]\n]+)\](?!\()');

/// Separators between the ids of one bracketed group.
final _separator = RegExp(r'[,;\s]+');

/// An inline code span: a run of backticks, its content, and a closing run of
/// the same length.
final _codeSpan = RegExp(r'(`+)[\s\S]*?(?<!`)\1(?!`)');

/// A line that opens or closes a fenced code block, indented at most three
/// spaces. Any line starting with a fence run matches, info string or not.
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// `[n]` written as markdown that renders as exactly that, except directly
/// after a backtick or a backslash: there the renderer leaves the opening
/// entity undecoded, and shows `&#91;n]`.
///
/// Entities rather than backslash escapes: `\[…\]` can be display-math to the
/// renderer's LaTeX syntax, which would eat the brackets. An entity decodes to
/// plain text, never to a link delimiter, so `[2][3]` cannot read as a
/// reference link either.
String _bracketed(int number) => '&#91;$number&#93;';

/// [text] with each bracketed group of cited chunk ids replaced by the
/// numbers the source list shows for them.
///
/// [own] is this answer's source list, whose badges give the numbers. [thread]
/// is [threadCitationNumbers] over the whole thread, naming a source cited
/// elsewhere in the thread that this answer's list does not hold.
///
/// The numbers are text, not links.
///
/// A group is rewritten only when every id in it is known, so prose that
/// happens to sit in brackets is left alone, as is an id the model damaged
/// while copying it.
///
/// Code spans, and fenced code blocks indented at most three spaces, are left
/// as written. An indented code block is rewritten, and a line inside a fence
/// that starts with a fence run, info string or not, closes that fence. Code
/// spans are matched across paragraphs, so a lone backtick can pair with one
/// in a later paragraph and leave the markers between them as written.
///
/// With [markdown] set the brackets are written so the markdown renderer shows
/// them as they are; unset, the markers are written as literal `[n]`, for the
/// clipboard.
String labelCitationMarkers(
  String text, {
  required List<SourceReference> own,
  required Map<String, int> thread,
  required bool markdown,
}) {
  if ((own.isEmpty && thread.isEmpty) || !text.contains('[')) return text;

  final numbers = <String, int>{};
  for (var position = 0; position < own.length; position++) {
    final number = citationBadgeNumber(own[position], position);
    for (final key in _keysOf(own[position])) {
      numbers.putIfAbsent(key, () => number);
    }
  }

  String label(Match match) {
    final ids = match[1]!.split(_separator).where((id) => id.isNotEmpty);
    final labels = <int>{};
    for (final id in ids) {
      final number = numbers[id] ?? thread[id];
      if (number == null) return match[0]!;
      labels.add(number);
    }
    if (labels.isEmpty) return match[0]!;
    return labels
        .map((number) => markdown ? _bracketed(number) : '[$number]')
        .join();
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
