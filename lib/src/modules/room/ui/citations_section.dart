import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/copy_button.dart';
import '../../../shared/failed_image.dart';
import '../../../shared/preview_icon_button.dart';
import '../../../shared/zoomable_image.dart';
import '../../../shared/zoomable_view.dart';
import '../document_browser_url.dart';
import 'document_source.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';
import 'markdown/log_source.dart';
import 'paged_zoomable_images.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.citations');

/// Fixed size of a cited-figure thumbnail — its width and height, the figure
/// strip's height, and the error-slot width.
/// Not on the spacing scale — a component dimension, kept in one place.
const double _figureThumbnailSize = 120;

/// Fallback label shown when a cited figure can't be decoded.
const String _figureUnavailableLabel = 'Figure unavailable';

/// Fallback semantic label for a cited figure that has no caption.
const String _figureSemanticLabel = 'Cited figure';

class CitationsSection extends StatefulWidget {
  const CitationsSection({
    super.key,
    required this.sourceReferences,
    this.onShowChunkVisualization,
  });

  final List<SourceReference> sourceReferences;
  final void Function(SourceReference)? onShowChunkVisualization;

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
  });

  final SourceReference sourceReference;
  final int badgeNumber;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(SourceReference)? onShowChunkVisualization;

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
          // The cited document's source link: the viewer `source_url`, else a
          // resolver-derived URL from the document URI, else the raw URI as
          // text (it is never itself launchable). A fork supplies the resolver
          // via documentBrowserUrlResolverProvider.
          Padding(
            padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
            child: Consumer(
              builder: (context, ref, _) => DocumentSource(
                url: resolveDocumentBrowserUrl(
                  ref.watch(documentBrowserUrlResolverProvider),
                  sourceUrl: sourceReference.sourceUrl,
                  documentUri: sourceReference.documentUri,
                ),
                documentUri: sourceReference.documentUri,
              ),
            ),
          ),
          if (sourceReference.figures.isNotEmpty)
            _CitationFigures(sourceReference: sourceReference),
          if (sourceReference.headings.isNotEmpty) ...[
            const SizedBox(height: SoliplexSpacing.s2),
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
          ],
          if (sourceReference.content.isNotEmpty) ...[
            // Figures otherwise sit flush on the content card; supply the
            // section gap the headings block would give when it is absent.
            if (sourceReference.figures.isNotEmpty &&
                sourceReference.headings.isEmpty)
              const SizedBox(height: SoliplexSpacing.s2),
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
          ],
          const SizedBox(height: SoliplexSpacing.s2),
          _metaLine(context, theme, 'chunk id', sourceReference.chunkId),
        ],
      ),
    );
  }

  /// A single provenance line: a muted-bold [label] lead-in followed by a
  /// monospace [value] that wraps to the margin, so the full uri / chunk id
  /// stays visible without a hanging indent.
  Widget _metaLine(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: value,
              style: context.monospaceOn(
                theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontally-scrolling strip of the cited figures whose bytes the
/// backend shipped in state. Refs without bytes (expansion-introduced) are
/// skipped — they remain viewable via chunk visualization.
class _CitationFigures extends StatelessWidget {
  const _CitationFigures({required this.sourceReference});

  final SourceReference sourceReference;

  void _openBrowser(BuildContext context, int index) {
    final figures = sourceReference.figures;
    showZoomableMediaDialog(
      context,
      viewer: PagedZoomableImages(
        itemCount: figures.length,
        initialIndex: index,
        autofocus: true,
        pageBuilder: (context, i, rotation) {
          final figure = figures[i];
          return ZoomableImage.controlledRotation(
            bytes: figure.bytes,
            semanticLabel: figure.caption ?? _figureSemanticLabel,
            logSource: figure.ref,
            rotationQuarterTurns: rotation.quarterTurns,
            onRotate: rotation.onRotate,
            decodeFailureChild:
                const FailedImage(label: _figureUnavailableLabel),
          );
        },
        footerBuilder: (context, i) {
          final caption = figures[i].caption;
          return caption != null ? _FigureCaption(caption: caption) : null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final figures = sourceReference.figures;
    return Padding(
      padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
      child: SizedBox(
        height: _figureThumbnailSize,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: figures.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: SoliplexSpacing.s2),
          itemBuilder: (context, index) => _FigureThumbnail(
            figure: figures[index],
            onTap: () => _openBrowser(context, index),
          ),
        ),
      ),
    );
  }
}

/// One cited-figure thumbnail rendered from in-state bytes. Tapping opens a
/// zoomable browser over the citation's figures. A decode failure shows a
/// broken-image fallback.
class _FigureThumbnail extends StatelessWidget {
  const _FigureThumbnail({required this.figure, required this.onTap});

  final Figure figure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.radii.md),
        child: Image.memory(
          figure.bytes,
          width: _figureThumbnailSize,
          height: _figureThumbnailSize,
          fit: BoxFit.cover,
          semanticLabel: figure.caption ?? _figureSemanticLabel,
          errorBuilder: (context, error, stack) {
            logFailedSourceOnce(
              _logger,
              'cited figure decode failed: ${figure.ref}',
              figure.ref,
              error: error,
              stackTrace: stack,
            );
            return const SizedBox(
              width: _figureThumbnailSize,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: FailedImage(label: _figureUnavailableLabel),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A cited figure's caption beneath the full-size image. Collapses to two
/// lines with a `more` toggle; the toggle appears only when the text actually
/// overflows. Expanded text scrolls within a bounded band so a long caption
/// never pushes the image off-screen.
class _FigureCaption extends StatefulWidget {
  const _FigureCaption({required this.caption});

  final String caption;

  @override
  State<_FigureCaption> createState() => _FigureCaptionState();
}

class _FigureCaptionState extends State<_FigureCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overflows = _overflowsTwoLines(
            widget.caption,
            style,
            constraints.maxWidth,
            Directionality.of(context),
            textScaler,
          );
          final text = Text(
            widget.caption,
            style: style,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expanded)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(child: text),
                )
              else
                text,
              if (overflows)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
                    child: Text(
                      _expanded ? 'less' : 'more',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static bool _overflowsTwoLines(
    String text,
    TextStyle? style,
    double maxWidth,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: direction,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
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
  lines.add('chunk id: ${ref.chunkId}');
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
