import 'package:markdown/markdown.dart' as md;
import 'package:soliplex_agent/soliplex_agent.dart';

/// The number a citation is shown under: the backend's `index`, which holds
/// across the conversation, or its place in the list when the backend reports
/// none.
///
/// Shared by the source list's badge and the marker in the answer's text, so
/// the two cannot disagree about which number names a source.
int citationBadgeNumber(SourceReference ref, int position) =>
    ref.index ?? position + 1;

/// Every chunk id in [turns] whose citation carries a backend `index`, mapped
/// to that index.
///
/// Only those citations are taken: that number is assigned once per chunk id
/// and kept for the conversation, so it names the same source whichever turn's
/// text uses it. A positional fallback means nothing outside the list it was
/// counted in.
Map<String, int> threadCitationNumbers(
  Iterable<List<SourceReference>> turns,
) {
  final numbers = <String, int>{};
  for (final refs in turns) {
    for (final ref in refs) {
      final index = ref.index;
      if (index == null) continue;
      numbers.putIfAbsent(ref.chunkId, () => index);
    }
  }
  return numbers;
}

/// The numbers one answer's markers are labelled with: [thread]'s, with this
/// answer's own source list, [own], taking precedence by its badge numbers.
Map<String, int> answerCitationNumbers({
  required List<SourceReference> own,
  required Map<String, int> thread,
}) {
  final numbers = <String, int>{};
  for (final (position, ref) in own.indexed) {
    numbers.putIfAbsent(ref.chunkId, () => citationBadgeNumber(ref, position));
  }
  return {...thread, ...numbers};
}

/// A bracketed group the model may have cited with: `[a]`, `[a, b]`, `[a; b]`
/// or `[a b]`. A `!` directly before it is taken with it, since markdown reads
/// `![` as an image's opening.
///
/// A group with an escaped bracket, `\[a\]`, `\[a]` or `[a\]`, is never
/// labelled, so markdown reads it as it would without this syntax: as an
/// escape, display math, or part of a link outside it. Markdown takes `\[`
/// before this syntax sees its `[`, and the last id of `[a\]` keeps its
/// backslash, so no number names it.
final _marker = RegExp(r'(!?)\[([^\[\]\n]+)\]');

/// Separators between the ids of one bracketed group.
final _separator = RegExp(r'[,;\s]+');

/// The entries of [numbers] for the ids [text]'s bracketed groups name: every
/// entry labelling [text] could read.
Map<String, int> citationNumbersIn(String text, Map<String, int> numbers) => {
      for (final marker in _marker.allMatches(text))
        for (final id in marker[2]!.split(_separator))
          if (numbers[id] case final number?) id: number,
    };

/// [marker], a match of [_marker], with its ids as the numbers [numbers] gives
/// them — `[4][2]` — or null when it holds no id or any id in it has none, so
/// prose that happens to sit in brackets, and an id the model damaged while
/// copying it, are left alone.
String? _label(Match marker, Map<String, int> numbers) {
  final labels = <int>{};
  for (final id in marker[2]!.split(_separator)) {
    if (id.isEmpty) continue;
    final number = numbers[id];
    if (number == null) return null;
    labels.add(number);
  }
  if (labels.isEmpty) return null;
  return '${marker[1]}${labels.map((number) => '[$number]').join()}';
}

/// Whether markdown reads the start of [source] as a link or an image, given
/// the link reference definitions of its document, [references]: `[a](url)`,
/// `[a][ref]`, `[a]` naming a definition, or `![a](url)`.
bool _opensLink(String source, Map<String, md.LinkReference> references) {
  final document = md.Document(encodeHtml: false)
    ..linkReferences.addAll(references);
  final first = md.InlineParser(source, document).parse().firstOrNull;
  return first is md.Element && (first.tag == 'a' || first.tag == 'img');
}

/// A reference link's label as markdown reads one after a link's text: up to
/// its first `]` not escaped by a backslash, and no further than a `[`, at
/// which markdown gives up on it.
final _referenceLabel = RegExp(r'\[(?:\\[\s\S]|[^\\\[\]])*\]?');

/// Shows each bracketed group of cited chunk ids in an answer's markdown as
/// their numbers, in plain text.
///
/// Inline syntaxes never run inside a code block, and a code span is consumed
/// whole from its opening backtick, so ids in code are left as written. A
/// group it cannot label, or that markdown reads as a link or an image, is
/// declined, and the parser reads it as it would without this syntax: a link,
/// an image, bracketed prose, or an id.
///
/// Markdown reads what follows a group's `]` as part of a link only when it is
/// `[`, a reference's label, or `(`, an inline link's destination and title.
/// So the group is asked about alone, with its label, or, before a `(`, with
/// the rest of the inline text it sits in, since a destination and title can
/// run on over several lines.
class CitationMarkerSyntax extends md.InlineSyntax {
  CitationMarkerSyntax(this._numbers) : super(_marker.pattern);

  final Map<String, int> _numbers;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final source = parser.source;
    final start = startMatchPos ?? parser.pos;
    final group = _marker.matchAsPrefix(source, start);
    if (group == null || _label(group, _numbers) == null) return false;
    final end = switch (group.end < source.length ? source[group.end] : '') {
      '[' => _referenceLabel.matchAsPrefix(source, group.end)!.end,
      '(' => source.length,
      _ => group.end,
    };
    if (_opensLink(
      source.substring(start, end),
      parser.document.linkReferences,
    )) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(_label(match, _numbers)!));
    return true;
  }
}
