import 'package:flutter/material.dart';

import '../../../shared/browser_url_link.dart';

/// A document's source, shown in a link slot.
///
/// Renders a clickable [BrowserUrlLink] for the launchable [url]; when there is
/// none, the [documentUri] is shown as muted, non-clickable text (the full
/// value on hover), since the URI is never itself launchable. Renders nothing
/// when neither is available.
class DocumentSource extends StatelessWidget {
  const DocumentSource({
    required this.url,
    required this.documentUri,
    super.key,
  });

  /// The document's launchable browser URL, or null.
  final Uri? url;

  /// The document's internal URI, shown as text when [url] is null.
  final String documentUri;

  @override
  Widget build(BuildContext context) {
    final linkUrl = url;
    if (linkUrl != null) return BrowserUrlLink(url: linkUrl);

    if (documentUri.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Tooltip(
      message: documentUri,
      child: Text(
        documentUri,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
