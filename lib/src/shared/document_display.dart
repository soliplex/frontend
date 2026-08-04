import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Maps a lowercase file extension to a recognizable Material icon, falling
/// back to [Icons.insert_drive_file] for an unknown or missing one.
IconData _iconForExtension(String extension) => switch (extension) {
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.description,
      'xls' || 'xlsx' => Icons.table_chart,
      'ppt' || 'pptx' => Icons.slideshow,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Icons.image,
      'txt' || 'md' => Icons.article,
      _ => Icons.insert_drive_file,
    };

/// Extracts the lowercase extension from [filename].
///
/// Returns an empty string when there is no dot with characters after it.
String _extensionOfName(String filename) {
  final lastDot = filename.lastIndexOf('.');
  if (lastDot == -1 || lastDot == filename.length - 1) {
    return '';
  }

  return filename.substring(lastDot + 1).toLowerCase();
}

/// A document as a row presents it: the name it is labelled with, the glyph for
/// its type, the documents it is embedded in, and whichever title that name has
/// not already said.
///
/// [icon] is read off [name] rather than off the URI, so the glyph describes
/// whatever the row is labelled with — an embedded file reflects its own type,
/// not its container's. That agreement is structural rather than two branches
/// kept in step.
///
/// The URI is parsed once per instance, so a row reading several of these facts
/// pays for one parse.
@immutable
class DocumentDisplay {
  DocumentDisplay(this.document) : _ref = DocumentRef.parse(document.uri);

  /// The document being presented. Public because a row needs its id, its
  /// metadata and its source URL as well as the facts derived here.
  final RagDocument document;

  final DocumentRef _ref;

  /// [document]'s title, or null when it has none or carries one that reads
  /// blank.
  ///
  /// The single reading of "has a title", so [name] and [unstatedTitle] cannot
  /// answer that question two different ways.
  String? get _title {
    final title = document.title?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  /// The name to label this document with: the filename its URI names — an
  /// embedded file's own name, not its container's — then [RagDocument.title],
  /// then the URI itself.
  ///
  /// See [DocumentRef.displayName] for when a URI names no file. A title is a
  /// genuine second choice; the last two tiers are labels of last resort — the
  /// raw URI is the most legible thing left that tells this row apart from
  /// another, and `Untitled` covers a document whose URI says nothing at all.
  ///
  /// A title or URI that reads blank is passed over rather than taken, so a
  /// label does not render as nothing — which would also leave the tooltip
  /// recovering a truncated name blank. Whitespace is what this reads as blank;
  /// a name of nothing but zero-width characters still renders as nothing.
  String get name =>
      _ref.displayName ??
      _title ??
      (document.uri.trim().isNotEmpty ? document.uri : 'Untitled');

  /// [document]'s title, unless [name] already states it.
  ///
  /// Null when the two would read the same — a URI naming no file leaves [name]
  /// showing the title, and a title can also simply repeat the filename — and
  /// null when there is no title. Stating it twice says nothing.
  String? get unstatedTitle => _title == name ? null : _title;

  /// The file-type glyph for [name].
  IconData get icon => _iconForExtension(_extensionOfName(name));

  /// The documents this one is embedded in, outermost first. Empty when it is
  /// not embedded in one.
  List<String> get ancestorNames => _ref.ancestorNames;
}

/// Filters [docs] by matching [query] against display name and URI.
///
/// Returns all documents when [query] is empty.
List<RagDocument> filterDocuments(List<RagDocument> docs, String query) {
  if (query.isEmpty) return docs;
  final q = query.toLowerCase();
  return docs
      .where(
        (d) =>
            DocumentDisplay(d).name.toLowerCase().contains(q) ||
            d.uri.toLowerCase().contains(q),
      )
      .toList();
}
