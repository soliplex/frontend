import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../copy_button.dart';

/// Which presentation of a piece of content a viewer shows.
enum ContentView { rendered, source }

/// The row above a viewer body: an optional label, an optional switch between
/// the rendered and source views, and a copy button.
class ContentHeader extends StatelessWidget {
  const ContentHeader({
    super.key,
    this.label,
    required this.copyText,
    required this.copyTooltip,
    this.view,
    this.renderedLabel,
    this.onViewChanged,
  }) : assert(
          view == null || (renderedLabel != null && onViewChanged != null),
          'a view switch needs renderedLabel and onViewChanged',
        );

  final String? label;
  final String copyText;
  final String copyTooltip;
  final ContentView? view;
  final String? renderedLabel;
  final ValueChanged<ContentView>? onViewChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    final view = this.view;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: label == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(
                      left: SoliplexSpacing.s3,
                      top: SoliplexSpacing.s1,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          // Laid out before the label, so the switch and copy button get the
          // width they need and the label is cut short first; the switch
          // shrinks only when it cannot fit beside the copy button at all.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (view != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SegmentedButton<ContentView>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: theme.textTheme.labelSmall,
                          ),
                          segments: [
                            ButtonSegment(
                              value: ContentView.rendered,
                              label: Text(renderedLabel!),
                            ),
                            const ButtonSegment(
                              value: ContentView.source,
                              label: Text('Source'),
                            ),
                          ],
                          selected: {view},
                          onSelectionChanged: (selection) =>
                              onViewChanged!(selection.single),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    right: SoliplexSpacing.s1,
                    top: SoliplexSpacing.s1,
                  ),
                  child: CopyButton(
                    text: copyText,
                    tooltip: copyTooltip,
                    iconSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar in error colours explaining that a viewer could not show its content
/// as asked.
class RenderFailureNotice extends StatelessWidget {
  const RenderFailureNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _NoticeBar(
      message: message,
      icon: Icons.warning_amber_outlined,
      background: colors.errorContainer,
      foreground: colors.onErrorContainer,
    );
  }
}

/// A bar in neutral colours explaining why a viewer shows something other than
/// usual, without a failure.
class ContentInfoNotice extends StatelessWidget {
  const ContentInfoNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _NoticeBar(
      message: message,
      icon: Icons.info_outline,
      background: colors.surfaceContainerHighest,
      foreground: colors.onSurfaceVariant,
    );
  }
}

/// The layout both notices share; they differ in icon and colours.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({
    required this.message,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      color: background,
      child: Row(
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chrome around a viewer body: [header] and [notice] above [body].
///
/// Inline, the frame is as tall as its body, which may cap its own height.
/// Filling, it takes the height it is given and needs it bounded: header and
/// notice stay put and the body takes the rest. When [scrollBody] is set, the
/// body scrolls vertically and is at least the rest's height. A body that
/// scrolls or pans itself sets [scrollBody] to false and is given that height.
class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.header,
    this.notice,
    required this.body,
    required this.fill,
    this.scrollBody = true,
  });

  final Widget header;
  final Widget? notice;
  final Widget body;
  final bool fill;
  final bool scrollBody;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        0,
        SoliplexSpacing.s3,
        SoliplexSpacing.s3,
      ),
      child: body,
    );
    final notice = this.notice;
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (notice != null) notice,
        if (!fill)
          padded
        else if (!scrollBody)
          Expanded(child: padded)
        else
          // At least the page's height, so a short body's own background
          // reaches the bottom of the page, as in a file viewer, instead of
          // ending below its last line.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: padded,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
