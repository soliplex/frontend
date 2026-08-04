import 'dart:convert';

import 'package:meta/meta.dart';

/// The marker the backend appends to a container's URI for each file embedded
/// in it, with the name percent-encoded (`quote(name, safe='')`).
const _attachmentMarker = '#attachment=';

/// A document URI decomposed into the document it lives in and the chain of
/// attachment names leading to it.
///
/// The backend ingests files embedded in a PDF as separate, first-class
/// documents and encodes the relationship in the URI:
///
/// ```text
/// file:///docs/annual-report.pdf#attachment=budget.xlsx
/// file:///docs/a.pdf#attachment=b.pdf#attachment=inner.xlsx
/// ```
///
/// This is pure URI structure and knows nothing about document titles;
/// callers compose the two.
@immutable
class DocumentRef {
  const DocumentRef._({required this.rootUri, required this.attachmentPath});

  /// Decomposes [uri] into its root and attachment names.
  ///
  /// Splits on the literal `#attachment=` rather than reading [Uri.fragment],
  /// because a nested URI carries two unencoded `#` separators and URI parsing
  /// re-encodes the second one as `%23`.
  ///
  /// Every [String] yields a ref and none throws: a string with no marker
  /// simply has no attachments.
  ///
  /// A segment that decodes to nothing is dropped rather than kept as a level,
  /// so a trailing `#attachment=` degrades to the containing document.
  factory DocumentRef.parse(String uri) {
    final segments = uri.split(_attachmentMarker);
    return DocumentRef._(
      rootUri: segments.first,
      attachmentPath: List.unmodifiable(
        segments.skip(1).map(_decode).where((name) => name.isNotEmpty),
      ),
    );
  }

  /// The URI of the outermost document, with every attachment segment
  /// stripped. A fragment ahead of the first attachment marker (e.g.
  /// `#page=3`) is left in place; anything after one belongs to that
  /// attachment's name.
  final String rootUri;

  /// Decoded attachment names from [rootUri] down to this document, outermost
  /// first. Empty for a plain document; no entry is the empty string, though
  /// one can be blank, since [DocumentRef.parse] drops only empty segments.
  ///
  /// One entry per nesting level, not a set of siblings: files embedded
  /// alongside each other are separate documents with separate URIs, each
  /// holding its own path off the same [rootUri].
  final List<String> attachmentPath;

  /// Whether this URI addresses a file embedded in another document.
  bool get isAttachment => attachmentPath.isNotEmpty;

  /// The innermost attachment name, or the decoded filename of [rootUri] when
  /// this is a plain document, trimmed of surrounding whitespace.
  ///
  /// Null when the name reads blank, so a caller that needs a label has to
  /// supply its own fallback rather than render an invisible one. For a plain
  /// document that covers a [rootUri] ending in a separator, or naming no path
  /// at all.
  ///
  /// Two surprises reach a plain document's name: an unescaped `?` or `#`
  /// truncates it, and a URI with no path (`https://example.test`) yields its
  /// host.
  String? get displayName {
    final name = (isAttachment ? attachmentPath.last : _rootFileName).trim();
    return name.isEmpty ? null : name;
  }

  /// The documents containing this one, outermost first, each trimmed the way
  /// [displayName] trims.
  ///
  /// For `a.pdf#attachment=b.pdf#attachment=c.xlsx` this is `[a.pdf, b.pdf]`.
  /// Empty when this is not an attachment. A name that reads blank contributes
  /// no entry, at any level, so joining these never yields a dangling
  /// separator.
  List<String> get ancestorNames {
    if (!isAttachment) return const [];
    return List.unmodifiable(
      [
        _rootFileName,
        ...attachmentPath.take(attachmentPath.length - 1),
      ].map((name) => name.trim()).where((name) => name.isNotEmpty),
    );
  }

  /// [rootUri]'s decoded filename, with any query or fragment dropped.
  ///
  /// Split before decoding: a `?` or `#` that is part of a filename arrives
  /// percent-escaped, and decoding first would turn it into a delimiter that
  /// truncates the name. The split therefore runs on the raw string, so an
  /// *unescaped* `?` or `#` does delimit — which is what resolves
  /// `a.pdf#page=3` to `a.pdf`, and what truncates a name that really contained
  /// one. Only a source storing already-decoded paths can hit the latter.
  ///
  /// Taking the last `/`-separated segment cannot tell an authority from a path,
  /// so a URI with no path at all (`https://example.test`) yields its host.
  String get _rootFileName {
    final path = rootUri.split('#').first.split('?').first;
    final lastSlash = path.lastIndexOf('/');
    return _decode(lastSlash == -1 ? path : path.substring(lastSlash + 1));
  }
}

/// One or more consecutive percent escapes, carrying a UTF-8 byte sequence.
/// Matched as a run so a multi-byte code point decodes as a unit.
final _escapeRun = RegExp('(?:%[0-9a-fA-F]{2})+');

/// Percent-decodes the escapes in [segment], leaving everything else alone.
///
/// Text outside an escape run is passed through untouched — including a raw
/// non-ASCII character or a `%` that begins no escape (`100%`) — and bytes that
/// are not legal UTF-8 become U+FFFD instead of aborting the name. That is what
/// makes [DocumentRef.parse] total.
///
/// [Uri.decodeComponent] is unusable here: it rejects a lone `%`, a raw
/// non-ASCII character, and any byte sequence that is not valid UTF-8, each by
/// throwing.
String _decode(String segment) => segment.replaceAllMapped(_escapeRun, (match) {
      final escapes = match[0]!;
      final bytes = [
        for (var i = 1; i < escapes.length; i += 3)
          int.parse(escapes.substring(i, i + 2), radix: 16),
      ];
      return utf8.decode(bytes, allowMalformed: true);
    });
