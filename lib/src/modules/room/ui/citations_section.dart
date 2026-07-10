import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/copy_button.dart';
import '../../../shared/failed_image.dart';
import '../../../shared/preview_icon_button.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.citations');

/// Fixed height (and loading/error-slot width) of a cited-figure thumbnail.
/// Not on the spacing scale — a component dimension, kept in one place.
const double _figureThumbnailSize = 120;

/// Fallback label shown when a cited figure can't be fetched or decoded.
const String _figureUnavailableLabel = 'Figure unavailable';

/// Fallback label shown when a cited figure genuinely doesn't exist (404).
/// Distinct from [_figureUnavailableLabel] because retrying won't help.
const String _figureNotFoundLabel = 'Figure not found';

/// Fetches the raw bytes of a cited picture ([pictureRef]) belonging to
/// [ref]'s document. Returns the image bytes or throws on failure.
typedef PictureFetcher = Future<Uint8List> Function(
  SourceReference ref,
  String pictureRef,
);

class CitationsSection extends StatefulWidget {
  const CitationsSection({
    super.key,
    required this.sourceReferences,
    this.onShowChunkVisualization,
    this.onFetchPicture,
  });

  final List<SourceReference> sourceReferences;
  final void Function(SourceReference)? onShowChunkVisualization;

  /// Fetches bytes for a citation's cited figures. When null, figures are
  /// not rendered even if a citation carries `pictureRefs`.
  final PictureFetcher? onFetchPicture;

  @override
  State<CitationsSection> createState() => _CitationsSectionState();
}

class _CitationsSectionState extends State<CitationsSection> {
  bool _sectionExpanded = false;
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.sourceReferences.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: SoliplexSpacing.s2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _sectionExpanded = !_sectionExpanded),
              borderRadius: BorderRadius.circular(context.radii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: SoliplexSpacing.s1,
                    horizontal: SoliplexSpacing.s1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.flip(
                      flipX: true,
                      child: Icon(
                        Icons.format_quote,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: SoliplexSpacing.s1),
                    Text(
                      '$count source${count == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: SoliplexSpacing.s1),
                    Icon(
                      _sectionExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (count > 0)
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: CopyButton(
                    icon: Icons.copy_all,
                    iconSize: 16,
                    tooltip: 'Copy all',
                    text: formatAllCitationsForClipboard(
                      widget.sourceReferences,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_sectionExpanded) ...[
          const SizedBox(height: SoliplexSpacing.s1),
          ...List.generate(widget.sourceReferences.length, (index) {
            final ref = widget.sourceReferences[index];
            return _SourceReferenceRow(
              sourceReference: ref,
              badgeNumber: ref.index ?? (index + 1),
              isExpanded: _expandedIndices.contains(index),
              onToggle: () => setState(() {
                if (_expandedIndices.contains(index)) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              }),
              onShowChunkVisualization: widget.onShowChunkVisualization,
              onFetchPicture: widget.onFetchPicture,
            );
          }),
        ],
      ],
    );
  }
}

class _SourceReferenceRow extends StatelessWidget {
  const _SourceReferenceRow({
    required this.sourceReference,
    required this.badgeNumber,
    required this.isExpanded,
    required this.onToggle,
    this.onShowChunkVisualization,
    this.onFetchPicture,
  });

  final SourceReference sourceReference;
  final int badgeNumber;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(SourceReference)? onShowChunkVisualization;
  final PictureFetcher? onFetchPicture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(context.radii.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: SoliplexSpacing.s1),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius:
                                BorderRadius.circular(context.radii.sm),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$badgeNumber',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: SoliplexSpacing.s2),
                        Expanded(
                          child: Text(
                            sourceReference.displayTitle,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sourceReference.formattedPageNumbers != null) ...[
                          const SizedBox(width: SoliplexSpacing.s1),
                          Text(
                            sourceReference.formattedPageNumbers!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (sourceReference.isPdf && onShowChunkVisualization != null)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: PreviewIconButton(
                      onTap: () => onShowChunkVisualization!(sourceReference),
                      tooltip: 'View source PDF',
                    ),
                  ),
                ),
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: CopyButton(
                    text: formatCitationForClipboard(sourceReference),
                    tooltip: 'Copy citation $badgeNumber',
                    iconSize: 16,
                  ),
                ),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(context.radii.md),
                child: Padding(
                  padding: const EdgeInsets.all(SoliplexSpacing.s2),
                  child: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (isExpanded) _buildExpandedContent(context, theme),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(
          left: SoliplexSpacing.s6, bottom: SoliplexSpacing.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sourceReference.documentUri.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
              child: Text(
                sourceReference.documentUri,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (sourceReference.headings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
              child: Text(
                sourceReference.headings.join(' > '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (sourceReference.content.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              padding: const EdgeInsets.all(SoliplexSpacing.s2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(context.radii.md),
              ),
              child: SingleChildScrollView(
                child: FlutterMarkdownPlusRenderer(
                  data: sourceReference.content,
                  selectable: false,
                ),
              ),
            ),
          if (sourceReference.pictureRefs.isNotEmpty && onFetchPicture != null)
            _CitationFigures(
              sourceReference: sourceReference,
              onFetchPicture: onFetchPicture!,
            ),
        ],
      ),
    );
  }
}

/// A horizontally-scrolling strip of the figures a citation cited, one
/// thumbnail per entry in [SourceReference.pictureRefs].
class _CitationFigures extends StatelessWidget {
  const _CitationFigures({
    required this.sourceReference,
    required this.onFetchPicture,
  });

  final SourceReference sourceReference;
  final PictureFetcher onFetchPicture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
      child: SizedBox(
        height: _figureThumbnailSize,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: sourceReference.pictureRefs.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: SoliplexSpacing.s2),
          itemBuilder: (context, index) => _FigureThumbnail(
            sourceReference: sourceReference,
            pictureRef: sourceReference.pictureRefs[index],
            onFetchPicture: onFetchPicture,
          ),
        ),
      ),
    );
  }
}

/// One cited-figure thumbnail. Lazily fetches its bytes; shows a spinner
/// while loading and a broken-image fallback on failure. Tapping opens a
/// zoomable full-size view.
class _FigureThumbnail extends StatefulWidget {
  const _FigureThumbnail({
    required this.sourceReference,
    required this.pictureRef,
    required this.onFetchPicture,
  });

  final SourceReference sourceReference;
  final String pictureRef;
  final PictureFetcher onFetchPicture;

  @override
  State<_FigureThumbnail> createState() => _FigureThumbnailState();
}

class _FigureThumbnailState extends State<_FigureThumbnail> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  void _retry() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<Uint8List> _fetch() async {
    _logger.debug(
      'fetching cited figure',
      attributes: {
        'documentId': widget.sourceReference.documentId,
        'pictureRef': widget.pictureRef,
      },
    );
    try {
      final bytes = await widget.onFetchPicture(
        widget.sourceReference,
        widget.pictureRef,
      );
      _logger.debug(
        'cited figure fetched',
        attributes: {
          'pictureRef': widget.pictureRef,
          'numBytes': bytes.length,
        },
      );
      return bytes;
    } on NotFoundException catch (error) {
      // A dangling picture_ref is a backend data issue, not a client fault
      // and not retryable — log at warning to avoid Sentry noise.
      _logger.warning(
        'cited figure not found',
        error: error,
        attributes: {'pictureRef': widget.pictureRef},
      );
      rethrow;
    } catch (error, stack) {
      _logger.error(
        'cited figure fetch failed',
        error: error,
        stackTrace: stack,
        attributes: {'pictureRef': widget.pictureRef},
      );
      rethrow;
    }
  }

  void _openFullSize(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) {
              _logger.warning(
                'cited figure decode failed (full-size)',
                error: error,
                attributes: {'pictureRef': widget.pictureRef},
              );
              return const FailedImage(label: _figureUnavailableLabel);
            },
          ),
        ),
      ),
    );
  }

  /// Broken-figure placeholder sized to fit the thumbnail strip. Scaled down
  /// so the FailedImage icon+label doesn't overflow the fixed strip height.
  /// When [retryable], the placeholder taps to re-run the fetch.
  Widget _fallback({required bool retryable, required String label}) {
    final failed = SizedBox(
      width: _figureThumbnailSize,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: FailedImage(label: label),
      ),
    );
    if (!retryable) return failed;
    return Tooltip(
      message: 'Tap to retry',
      child: InkWell(onTap: _retry, child: failed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radii.md),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                width: _figureThumbnailSize,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              final notFound = snapshot.error is NotFoundException;
              return _fallback(
                retryable: !notFound,
                label:
                    notFound ? _figureNotFoundLabel : _figureUnavailableLabel,
              );
            }
            final bytes = snapshot.data!;
            return InkWell(
              onTap: () => _openFullSize(bytes),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) {
                  _logger.warning(
                    'cited figure decode failed',
                    error: error,
                    attributes: {'pictureRef': widget.pictureRef},
                  );
                  return _fallback(
                    retryable: false,
                    label: _figureUnavailableLabel,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

@visibleForTesting
String formatCitationForClipboard(SourceReference ref) {
  final lines = <String>[ref.displayTitle];
  if (ref.headings.isNotEmpty) {
    lines.add(ref.headings.join(' > '));
  }
  final pages = ref.formattedPageNumbers;
  if (pages != null) {
    lines.add(pages);
  }
  if (ref.documentUri.isNotEmpty) {
    lines.add(ref.documentUri);
  }
  if (ref.content.isNotEmpty) {
    lines
      ..add('')
      ..add(ref.content);
  }
  return lines.join('\n');
}

@visibleForTesting
String formatAllCitationsForClipboard(List<SourceReference> refs) =>
    refs.map(formatCitationForClipboard).join('\n\n---\n\n');
