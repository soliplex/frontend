import 'package:flutter/foundation.dart';
import 'package:soliplex_client/soliplex_client.dart' show ServedFile;

/// A PDF the room can open, by where it lives.
///
/// Equal when they name the same file, so reopening one already open is
/// recognised as such.
@immutable
sealed class PdfOpenTarget {
  const PdfOpenTarget();

  /// The file name shown, and the name quotes are attributed to.
  String get title;

  /// Identifies the file among the room's: kept to identifiers, since it
  /// reaches pdfrx's caches and the logs.
  String get key;

  /// Whether the file belongs to one thread, so leaving the thread closes it.
  bool get isThreadScoped;

  @override
  bool operator ==(Object other) => other is PdfOpenTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A file uploaded to the room.
final class RoomUploadPdf extends PdfOpenTarget {
  const RoomUploadPdf({required this.roomId, required this.filename});

  final String roomId;
  final String filename;

  @override
  String get title => filename;

  @override
  String get key => 'room-upload:$roomId/$filename';

  @override
  bool get isThreadScoped => false;
}

/// A file uploaded to a thread.
final class ThreadUploadPdf extends PdfOpenTarget {
  const ThreadUploadPdf({
    required this.roomId,
    required this.threadId,
    required this.filename,
  });

  final String roomId;
  final String threadId;
  final String filename;

  @override
  String get title => filename;

  @override
  String get key => 'thread-upload:$roomId/$threadId/$filename';

  @override
  bool get isThreadScoped => true;
}

/// A file in a thread's workspace.
final class WorkdirPdf extends PdfOpenTarget {
  const WorkdirPdf({
    required this.roomId,
    required this.threadId,
    required this.file,
  });

  final String roomId;
  final String threadId;
  final ServedFile file;

  @override
  String get title => file.basename;

  @override
  String get key => 'workdir:$roomId/$threadId/${file.filename}';

  @override
  bool get isThreadScoped => true;
}

/// A public PDF an answer linked to.
final class LinkPdf extends PdfOpenTarget {
  const LinkPdf(this.uri);

  final Uri uri;

  @override
  String get title {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? uri.host : segments.last;
  }

  /// Host and path only: a link's query is where it would carry a token.
  @override
  String get key => 'link:${uri.host}${uri.path}';

  @override
  bool get isThreadScoped => false;
}

/// A passage the user selected in a PDF and asked about.
///
/// Sent ahead of the next message as markdown quote blocks (see
/// `formatQuotedContext`), the one channel that reaches the model: the
/// backend keeps AG-UI `context` items without passing them on.
@immutable
class PdfQuote {
  const PdfQuote({
    required this.text,
    required this.documentTitle,
    required this.pageNumber,
    this.source,
  });

  /// The selected text, whitespace collapsed to single spaces.
  final String text;

  /// The file it came from, as the viewer titled it.
  final String documentTitle;

  /// The page the selection starts on, 1-based.
  final int pageNumber;

  /// Where the file lives, when the quote was taken in this session. A quote
  /// read back from a sent message knows only its file's name.
  final PdfOpenTarget? source;

  /// The first [maxLength] characters of [text], for a chip.
  String excerpt([int maxLength = 60]) => text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength).trimRight()}…';

  /// Ignores [source]: the same passage quoted twice is one quote, however
  /// it was reached.
  @override
  bool operator ==(Object other) =>
      other is PdfQuote &&
      other.text == text &&
      other.documentTitle == documentTitle &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => Object.hash(text, documentTitle, pageNumber);
}
