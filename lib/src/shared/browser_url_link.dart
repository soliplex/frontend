import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'markdown/launch_markdown_link.dart';

/// Display text for a browser URL: scheme (and any query/fragment) removed so
/// the origin reads as `host/path` without `https://` noise.
String browserUrlDisplay(Uri url) => '${url.host}${url.path}';

/// A clickable document origin link: a link icon plus the scheme-stripped
/// origin, opening [url] in the platform's default handler (a new browser tab
/// on web). The raw `https://` is hidden to reduce noise.
///
/// The whole address is on the link's tooltip, since the displayed text drops
/// the scheme, the query and the fragment and then ellipsizes what is left —
/// so the tooltip is the only place the address being opened reads in full.
class BrowserUrlLink extends StatelessWidget {
  const BrowserUrlLink({required this.url, super.key});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => launchMarkdownLink(url.toString()),
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: SoliplexSpacing.s1),
            Flexible(
              child: Tooltip(
                message: url.toString(),
                waitDuration: const Duration(milliseconds: 500),
                child: Text(
                  browserUrlDisplay(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
