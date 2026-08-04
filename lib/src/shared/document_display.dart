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
/// its type, and the documents it is embedded in.
///
/// [icon] is read off [name] rather than off the URI, so the glyph always
/// describes the file the row is labelled with — an attachment reflects the
/// embedded file's own type, not its container's. That agreement is structural
/// rather than two branches kept in step.
///
/// The URI is parsed once per instance, so a row reading several of these facts
/// pays for one parse.
@immutable
class DocumentDisplay {
  DocumentDisplay(this.document) : _ref = DocumentRef.parse(document.uri);

  final RagDocument document;

  final DocumentRef _ref;

  /// The name to label this document with: the filename its URI names — an
  /// embedded file's own name, not its container's — then [RagDocument.title],
  /// then the URI itself.
  ///
  /// The URI names no file when it is empty, ends in `/`, is a bare UUID
  /// standing in for a path, or addresses an embedded file whose own name reads
  /// blank. A title is a genuine second choice; the last two tiers are labels of
  /// last resort — the raw URI is the only string left that tells this row apart
  /// from another, and `Untitled` covers a document stored with no URI at all.
  ///
  /// A title that reads blank is passed over rather than taken, so no tier can
  /// resolve to a label that renders as nothing — which would also leave the
  /// tooltip recovering a truncated name blank.
  String get name {
    final fileName = _ref.displayName;
    if (fileName != null) return fileName;
    final title = document.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return document.uri.isNotEmpty ? document.uri : 'Untitled';
  }

  /// [document]'s title, when [name] does not already state it.
  ///
  /// Null when the URI named no file, because [name] is then the title itself
  /// and stating it twice says nothing, and null when there is no title.
  String? get unstatedTitle => _ref.displayName == null ? null : document.title;

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
