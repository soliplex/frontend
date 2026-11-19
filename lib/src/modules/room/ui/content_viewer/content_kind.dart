/// How the content viewer renders a piece of content.
enum ContentKind { svg, json, code }

/// The kind of viewer for [language], a highlight language id.
/// Case-insensitive; only `svg` and `json` have their own viewers.
ContentKind contentKindOf(String language) => switch (language.toLowerCase()) {
      'svg' => ContentKind.svg,
      'json' => ContentKind.json,
      _ => ContentKind.code,
    };

/// The language of a markdown fence given its [infoString]: the first
/// whitespace-separated word, lower-cased, or `plaintext` when there is none.
String fenceLanguage(String? infoString) {
  final words = (infoString ?? '').trim().split(RegExp(r'\s+'));
  final first = words.first;
  return first.isEmpty ? 'plaintext' : first.toLowerCase();
}
