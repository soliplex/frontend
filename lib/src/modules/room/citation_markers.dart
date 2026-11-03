import 'package:markdown/markdown.dart' as md;
import 'package:soliplex_agent/soliplex_agent.dart';

/// The number a citation is shown under: the backend's `index`, or its place
/// in the list when the capability reports none.
///
/// Shared by the source list's badge and the marker in the answer's text, so
/// the two cannot disagree about which number names a source.
int citationBadgeNumber(SourceReference ref, int position) =>
    ref.index ?? position + 1;

/// Every chunk id cited anywhere in a thread by a citation carrying a backend
/// `index`, mapped to that index.
///
/// Only citations carrying a backend `index` are taken: the backend keeps each
/// cited chunk's citation, `index` included, in a `citation_index` that spans
/// the conversation, so the number names the same source whichever turn's text
/// uses it. A positional fallback means nothing outside the list it was
/// counted in.
Map<String, int> threadCitationNumbers(
  Iterable<List<SourceReference>> turns,
) =>
    {
      for (final refs in turns)
        for (final ref in refs)
          if (ref.index case final index?) ref.chunkId: index,
    };

/// The numbers one answer's markers are labelled with: [thread]'s, with this
/// answer's own source list, [own], taking precedence by its badge numbers.
Map<String, int> answerCitationNumbers({
  required List<SourceReference> own,
  required Map<String, int> thread,
}) =>
    {
      ...thread,
      for (final (position, ref) in own.indexed)
        ref.chunkId: citationBadgeNumber(ref, position),
    };

/// A bracketed group the model may have cited with: `[a]`, `[a, b]`, `[a; b]`,
/// or with its bracket escaped, `\[a]`, which shows as `[a]`. One directly
/// followed by `(` is a markdown link's text.
final _marker = RegExp(r'\\?\[([^\[\]\n]+)\](?!\()');

/// Separators between the ids of one bracketed group.
final _separator = RegExp(r'[,;\s]+');

/// [ids], the inside of one bracketed group, as the numbers [numbers] gives
/// them — `[4][2]` — or null when any id in it has none, so prose that happens
/// to sit in brackets, and an id the model damaged while copying it, is left
/// alone.
String? _label(String ids, Map<String, int> numbers) {
  final labels = <int>{};
  for (final id in ids.split(_separator)) {
    if (id.isEmpty) continue;
    final number = numbers[id];
    if (number == null) return null;
    labels.add(number);
  }
  if (labels.isEmpty) return null;
  return labels.map((number) => '[$number]').join();
}

/// [text] with each bracketed group of cited chunk ids replaced by their
/// numbers, for the clipboard.
///
/// Markdown structure is not read, so an id in code is labelled too; the
/// answer bubble, which renders through [CitationMarkerSyntax], leaves it.
String labelCitationMarkers(String text, Map<String, int> numbers) {
  if (numbers.isEmpty) return text;
  return text.replaceAllMapped(
    _marker,
    (match) => _label(match[1]!, numbers) ?? match[0]!,
  );
}

/// Shows each bracketed group of cited chunk ids in an answer's markdown as
/// their numbers, in plain text.
///
/// The markdown parser offers an inline syntax only prose, so ids in code are
/// left as written. A group it cannot label is declined, and the parser reads
/// it as it would without this syntax: a link, bracketed prose, or an id.
class CitationMarkerSyntax extends md.InlineSyntax {
  CitationMarkerSyntax(this.numbers) : super(_marker.pattern);

  final Map<String, int> numbers;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final match =
        pattern.matchAsPrefix(parser.source, startMatchPos ?? parser.pos);
    if (match == null || _label(match[1]!, numbers) == null) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(_label(match[1]!, numbers)!));
    return true;
  }
}
