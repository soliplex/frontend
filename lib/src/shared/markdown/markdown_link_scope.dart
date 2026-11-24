import 'dart:async';

import 'package:flutter/widgets.dart';

import 'launch_markdown_link.dart';
import 'markdown_renderer.dart';

/// Lets a screen handle the links tapped in the markdown below it — the room
/// opens a PDF in its viewer — without a callback threaded through every
/// widget that renders a message.
///
/// Read at tap time, without subscribing, so nothing rebuilds when the
/// handler changes.
class MarkdownLinkScope extends InheritedWidget {
  const MarkdownLinkScope({
    super.key,
    required this.onLink,
    required super.child,
  });

  /// Offered each tapped link first. Returns whether it handled the link; a
  /// link it leaves goes where links go without a scope.
  final bool Function(String href) onLink;

  static MarkdownLinkScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MarkdownLinkScope>();

  @override
  bool updateShouldNotify(MarkdownLinkScope oldWidget) => false;
}

/// What tapping a markdown link does: [onLinkTap], when the renderer was
/// given one; otherwise the nearest [MarkdownLinkScope], if it takes the
/// link; otherwise the platform's handler for it.
void openMarkdownLink(
  BuildContext context,
  String href,
  String? title, {
  MarkdownLinkHandler? onLinkTap,
}) {
  if (onLinkTap != null) {
    onLinkTap(href, title);
    return;
  }
  if (MarkdownLinkScope.maybeOf(context)?.onLink(href) ?? false) return;
  unawaited(launchMarkdownLink(href));
}
