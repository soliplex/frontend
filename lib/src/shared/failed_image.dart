import 'package:flutter/material.dart';

import '../design/design.dart';
import 'copy_button.dart';

const double _iconBoxSize = 96;
const double _sourceMaxHeight = 200;

/// Visible placeholder for an image that could not be loaded or decoded.
///
/// When [source] is provided, a toolbar lets the user reveal the raw source
/// (data URI, http URL, file path, …) as selectable monospace text and copy
/// it. When [source] is null, only the icon and label are shown.
class FailedImage extends StatefulWidget {
  const FailedImage({this.source, this.label, super.key});

  /// The original URI/path the image failed to load from. When non-null the
  /// widget shows a toolbar with a preview/source toggle and a copy button.
  final String? source;

  /// Display label shown in the toolbar (when [source] is set) and as the
  /// accessibility/fallback label for the icon body.
  final String? label;

  @override
  State<FailedImage> createState() => _FailedImageState();
}

class _FailedImageState extends State<FailedImage> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSource = widget.source != null;

    final body = _showSource && hasSource
        ? _sourceView(theme, widget.source!)
        : Center(child: _iconBox(theme));

    if (!hasSource) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
            child: Text(
              _displayLabel(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SoliplexSpacing.s3, 0, SoliplexSpacing.s3, SoliplexSpacing.s3),
          child: body,
        ),
      ],
    );
  }

  Widget _iconBox(ThemeData theme) {
    final label = _displayLabel();
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: _iconBoxSize,
        height: _iconBoxSize,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(soliplexRadii.sm),
        ),
        child: Icon(
          Icons.broken_image,
          color: theme.colorScheme.onSurfaceVariant,
          size: 32,
        ),
      ),
    );
  }

  Widget _sourceView(ThemeData theme, String source) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _sourceMaxHeight),
      child: SingleChildScrollView(
        child: SelectableText(
          source,
          style: context.monospaceOn(theme.textTheme.bodySmall).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  Widget _toolbar(ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: SoliplexSpacing.s3, top: SoliplexSpacing.s1),
          child: Text(_displayLabel(), style: labelStyle),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
          child: Tooltip(
            message: _showSource ? 'Show preview' : 'Show source',
            child: InkWell(
              borderRadius: BorderRadius.circular(soliplexRadii.sm),
              onTap: () => setState(() => _showSource = !_showSource),
              child: Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s1),
                child: Icon(
                  _showSource ? Icons.image : Icons.code,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
              right: SoliplexSpacing.s1, top: SoliplexSpacing.s1),
          child: CopyButton(
            text: widget.source!,
            tooltip: 'Copy source',
            iconSize: 16,
          ),
        ),
      ],
    );
  }

  String _displayLabel() {
    final l = widget.label;
    if (l != null && l.isNotEmpty) return l;
    return 'Image failed to load';
  }
}
