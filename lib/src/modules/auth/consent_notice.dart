import 'package:flutter/foundation.dart' show immutable;

/// Optional consent notice shown before authentication.
///
/// Flavors provide this when legal/compliance requires user acknowledgment
/// before connecting to a server.
@immutable
class ConsentNotice {
  const ConsentNotice({
    required this.title,
    required this.body,
    this.acknowledgmentLabel = 'OK',
  });

  final String title;

  /// Markdown body, rendered as prose (paragraphs, lists, emphasis, links).
  ///
  /// Author/flavor-provided and trusted — it is compiled in, not server-sourced.
  /// If this ever becomes server-sourced, rendered links are a phishing vector
  /// and the input must be sanitized before rendering.
  final String body;

  final String acknowledgmentLabel;
}
