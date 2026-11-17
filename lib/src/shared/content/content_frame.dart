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
    return Row(
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(
              left: SoliplexSpacing.s3,
              top: SoliplexSpacing.s1,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Spacer(),
        if (view != null)
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
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
    );
  }
}

/// A bar explaining why a viewer shows something other than what was asked.
class RenderFailureNotice extends StatelessWidget {
  const RenderFailureNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chrome around a viewer body: [header] and [notice] above [body].
///
/// Inline, the frame is as tall as its content. Filling, it takes the height
/// it is given: header and notice stay put and the body takes the rest,
/// scrolling vertically when [scrollBody] is set. A body that scrolls or
/// pans itself sets [scrollBody] to false and is given that height.
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
        else
          Expanded(
            child: scrollBody ? SingleChildScrollView(child: padded) : padded,
          ),
      ],
    );
  }
}
