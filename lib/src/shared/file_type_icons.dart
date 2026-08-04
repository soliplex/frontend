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

/// The filename [doc]'s URI addresses, or null when the URI names none.
///
/// An empty URI and a bare UUID are ids rather than paths, so they are rejected
/// before parsing — a UUID would otherwise read as a perfectly good filename.
String? _fileName(RagDocument doc) => doc.uri.isEmpty || _isUuid(doc.uri)
    ? null
    : DocumentRef.parse(doc.uri).displayName;

/// Returns a user-friendly display name for a [RagDocument].
///
/// Uses the filename from [RagDocument.uri] — the attachment's own name when
/// the URI addresses a file embedded in another document. Falls back to
/// [RagDocument.title] when the URI names no file, and when it is an id rather
/// than a path (an empty URI or a bare UUID, e.g. quiz items).
String documentDisplayName(RagDocument doc) => _fileName(doc) ?? doc.title;

/// Returns the file-type icon for a [RagDocument].
///
/// Reads the extension off the name [documentDisplayName] renders, so the glyph
/// always describes the file the row is labelled with: an attachment reflects
/// the embedded file's type, not its container's.
IconData documentTypeIcon(RagDocument doc) =>
    _iconForExtension(_extensionOfName(documentDisplayName(doc)));

/// Filters [docs] by matching [query] against display name and URI.
///
/// Returns all documents when [query] is empty.
List<RagDocument> filterDocuments(List<RagDocument> docs, String query) {
  if (query.isEmpty) return docs;
  final q = query.toLowerCase();
  return docs
      .where(
        (d) =>
            documentDisplayName(d).toLowerCase().contains(q) ||
            d.uri.toLowerCase().contains(q),
      )
      .toList();
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _isUuid(String s) => _uuidPattern.hasMatch(s);
