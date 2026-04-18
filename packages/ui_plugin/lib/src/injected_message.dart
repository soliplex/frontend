/// An ephemeral, client-only message injected into the chat area by a plugin.
///
/// Not persisted to the server, not part of the AG-UI stream. Disappears on
/// reload or navigation. Rendered as a visually distinct system bubble.
class InjectedMessage {
  const InjectedMessage({
    required this.id,
    required this.content,
    this.format = 'markdown',
    required this.createdAt,
  });

  final String id;
  final String content;

  /// `'markdown'` (default) or `'plain'`.
  final String format;

  final DateTime createdAt;
}
