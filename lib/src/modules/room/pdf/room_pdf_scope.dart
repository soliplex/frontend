import 'package:flutter/widgets.dart';

import 'pdf_quote.dart';

/// How the room's conversation reaches its PDF viewer: a message's quote
/// cards reopen the file a quote came from, without a callback threaded
/// through the timeline.
///
/// Read without subscribing, at tap time, so opening a PDF rebuilds no
/// message.
class RoomPdfScope extends InheritedWidget {
  const RoomPdfScope({
    super.key,
    required this.open,
    required this.openQuote,
    required super.child,
  });

  /// Opens [target] in the viewer.
  final void Function(PdfOpenTarget target) open;

  /// Opens the file [quote] came from, at its page.
  final void Function(PdfQuote quote) openQuote;

  /// The nearest scope, or null where there is no viewer to open.
  static RoomPdfScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RoomPdfScope>();

  @override
  bool updateShouldNotify(RoomPdfScope oldWidget) => false;
}
