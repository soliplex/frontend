import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Returns the appropriate icon for a document based on its file extension.
///
/// Maps common file types to recognizable Material icons:
/// - PDF files: [Icons.picture_as_pdf]
/// - Word documents (.doc, .docx): [Icons.description]
/// - Excel spreadsheets (.xls, .xlsx): [Icons.table_chart]
/// - PowerPoint presentations (.ppt, .pptx): [Icons.slideshow]
/// - Images (.png, .jpg, .jpeg, .gif, .webp, .bmp): [Icons.image]
/// - Text/markdown (.txt, .md): [Icons.article]
/// - Unknown/missing extensions: [Icons.insert_drive_file]
///
/// Extension matching is case-insensitive.
IconData getFileTypeIcon(String path) {
  final extension = _extractExtension(path);

  return switch (extension) {
    'pdf' => Icons.picture_as_pdf,
    'doc' || 'docx' => Icons.description,
    'xls' || 'xlsx' => Icons.table_chart,
    'ppt' || 'pptx' => Icons.slideshow,
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Icons.image,
    'txt' || 'md' => Icons.article,
    _ => Icons.insert_drive_file,
  };
}

/// Extracts the lowercase file extension from a path.
///
/// Returns an empty string if no extension is found.
String _extractExtension(String path) {
  // Remove query strings and fragments
  var cleanPath = path.split('?').first.split('#').first;

  // Remove file:// prefix if present
  if (cleanPath.startsWith('file://')) {
    cleanPath = cleanPath.substring(7);
  }

  // Get the filename (last path segment)
  final segments = cleanPath.split('/');
  final filename = segments.isNotEmpty ? segments.last : cleanPath;

  // Find the last dot that has characters after it
  final lastDot = filename.lastIndexOf('.');
  if (lastDot == -1 || lastDot == filename.length - 1) {
    return '';
  }

  return filename.substring(lastDot + 1).toLowerCase();
}

/// Returns a user-friendly display name for a [RagDocument].
///
/// Uses the filename from [RagDocument.uri] when it contains a file
/// path. Falls back to [RagDocument.title] when the URI is empty or
/// a bare UUID (e.g. quiz items).
String documentDisplayName(RagDocument doc) {
  final uri = doc.uri;
  if (uri.isEmpty || _isUuid(uri)) {
    return doc.title;
  }
  var path = uri;
  if (path.startsWith('file://')) {
    path = path.substring(7);
  }
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash == -1) return path;
  return path.substring(lastSlash + 1);
}

/// Returns the path used for file-type icon detection from a
/// [RagDocument]. Uses [RagDocument.uri] when available, falling
/// back to [RagDocument.title] for UUID or empty URIs.
String documentIconPath(RagDocument doc) {
  final uri = doc.uri;
  if (uri.isEmpty || _isUuid(uri)) return doc.title;
  return uri;
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
