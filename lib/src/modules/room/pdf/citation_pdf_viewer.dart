import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        CancelledException,
        DocumentBoxes,
        NotFoundException,
        PassageBox,
        SoliplexApi,
        SourceReference;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/pdf/pdf_document_view.dart';
import '../../../shared/pdf/pdf_source.dart';
import '../citation_markers.dart';
import 'pdf_quote.dart';
import 'pdf_targets.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.pdf_viewer');

/// Builds the viewer for a cited document: [source] opened at [page], with
/// [passage] marked once it is known, [banner] under its header, and
/// [loadOcrText] for whatever pages of it have no text of their own.
typedef CitationPaneBuilder = Widget Function(
  PdfViewerSource source, {
  required int page,
  required PdfPassage? passage,
  required Widget banner,
  required Future<List<PdfTextBlock>> Function() loadOcrText,
});

/// A cited document in the viewer, at the passage of the citation it was
/// opened from, with a strip naming that citation and stepping between the
/// thread's others in the same document.
///
/// Each citation's passage is asked of the server the first time it shows,
/// and kept. Until it arrives the viewer opens at the citation's page; if it
/// cannot be had, the strip says which page the passage is on.
class CitationPdfViewer extends StatefulWidget {
  const CitationPdfViewer({
    super.key,
    required this.target,
    required this.api,
    required this.pane,
    required this.onUnavailable,
  });

  final CitationPdfTarget target;
  final SoliplexApi api;
  final CitationPaneBuilder pane;

  /// The server has no file for the document — it was not ingested from one
  /// it can read, or the server predates the route — called with the
  /// citation showing, so its pages can be shown another way.
  final void Function(SourceReference citation) onUnavailable;

  @override
  State<CitationPdfViewer> createState() => _CitationPdfViewerState();
}

class _CitationPdfViewerState extends State<CitationPdfViewer> {
  late int _index = widget.target.active;

  /// Passages by chunk id, once loaded.
  final _passages = <String, PdfPassage>{};
  final _loading = <String>{};

  /// Chunks whose passage could not be had, or has no boxes to mark.
  final _unmarked = <String>{};

  SourceReference get _citation => widget.target.citations[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPassage());
  }

  @override
  void didUpdateWidget(CitationPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.target, widget.target)) return;
    if (oldWidget.target.key != widget.target.key) {
      _passages.clear();
      _unmarked.clear();
    }
    _index = widget.target.active;
    unawaited(_loadPassage());
  }

  void _select(int index) {
    setState(() => _index = index);
    unawaited(_loadPassage());
  }

  Future<void> _loadPassage() async {
    final citation = _citation;
    final chunkId = citation.chunkId;
    if (_passages.containsKey(chunkId) ||
        _unmarked.contains(chunkId) ||
        !_loading.add(chunkId)) {
      return;
    }
    final target = widget.target;
    try {
      final boxes = await widget.api.getDocumentBoxes(
        target.roomId,
        target.documentId,
        chunkIds: citation.chunkIds.isEmpty ? [chunkId] : citation.chunkIds,
        contextRefs: citation.docItemRefs,
        database: target.database,
      );
      if (!mounted) return;
      final passage = _passageOf(boxes);
      setState(() {
        if (passage == null) {
          _unmarked.add(chunkId);
        } else {
          _passages[chunkId] = passage;
        }
      });
    } on CancelledException {
      // Nothing to show; asked again when the citation next shows.
    } on Exception catch (error, stackTrace) {
      // The API client's exceptions carry status codes, hosts, paths and
      // the server's own reason; the ids are identifiers.
      _logger.warning(
        "Fetching a citation's passage failed",
        error: error,
        stackTrace: stackTrace,
        attributes: {'document': target.documentId, 'chunk': chunkId},
      );
      if (!mounted) return;
      setState(() => _unmarked.add(chunkId));
    } finally {
      _loading.remove(chunkId);
    }
  }

  static PdfPassage? _passageOf(DocumentBoxes boxes) {
    PdfPassageBox box(PassageBox b) => PdfPassageBox(
          page: b.page,
          left: b.left,
          top: b.top,
          right: b.right,
          bottom: b.bottom,
        );
    if (boxes.anchor.isEmpty && boxes.context.isEmpty) return null;
    return PdfPassage(
      anchor: [for (final b in boxes.anchor) box(b)],
      context: [for (final b in boxes.context) box(b)],
    );
  }

  /// The document's text as the server read it at ingestion — by OCR, for
  /// a scan — for the viewer to offer where the PDF has none.
  Future<List<PdfTextBlock>> _loadOcrText() async {
    final target = widget.target;
    final text = await widget.api.getDocumentText(
      target.roomId,
      target.documentId,
      database: target.database,
    );
    return [
      for (final block in text.blocks)
        PdfTextBlock(
          box: PdfPassageBox(
            page: block.box.page,
            left: block.box.left,
            top: block.box.top,
            right: block.box.right,
            bottom: block.box.bottom,
          ),
          text: block.text,
        ),
    ];
  }

  /// The source, its fetch watched for a server without the file.
  PdfViewerSource _source() {
    final source = pdfViewerSourceFor(widget.target, widget.api);
    final fetch = (source.load as PdfLoadBytes).fetch;
    return PdfViewerSource(
      title: source.title,
      origin: source.origin,
      cacheKey: source.cacheKey,
      sizeBytes: source.sizeBytes,
      load: PdfLoadBytes(() async {
        final Uint8List bytes;
        try {
          bytes = await fetch();
        } on NotFoundException {
          if (mounted) widget.onUnavailable(_citation);
          rethrow;
        }
        return bytes;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final citation = _citation;
    final chunkId = citation.chunkId;
    final passage = _passages[chunkId];
    final page = _pageOf(citation);
    return widget.pane(
      _source(),
      page: passage?.firstPage ?? page,
      passage: passage,
      loadOcrText: _loadOcrText,
      banner: _CitationStrip(
        citation: citation,
        position: _index,
        count: widget.target.citations.length,
        note: _unmarked.contains(chunkId)
            ? "Couldn't mark the passage — it's on page $page."
            : null,
        onSelect: _select,
      ),
    );
  }

  static int _pageOf(SourceReference citation) {
    final pages = citation.chunkPageNumbers.isNotEmpty
        ? citation.chunkPageNumbers
        : citation.pageNumbers;
    return pages.isEmpty ? 1 : pages.reduce((a, b) => a < b ? a : b);
  }
}

/// The citation the viewer is showing, and the way to the document's others.
class _CitationStrip extends StatelessWidget {
  const _CitationStrip({
    required this.citation,
    required this.position,
    required this.count,
    required this.note,
    required this.onSelect,
  });

  final SourceReference citation;
  final int position;
  final int count;
  final String? note;
  final void Function(int index) onSelect;

  String? get _pages {
    final pages = [
      ...(citation.chunkPageNumbers.isNotEmpty
          ? citation.chunkPageNumbers
          : citation.pageNumbers),
    ]..sort();
    if (pages.isEmpty) return null;
    return pages.first == pages.last
        ? 'p. ${pages.first}'
        : 'pp. ${pages.first}–${pages.last}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = [
      if (_pages case final pages?) pages,
      ...citation.headings.skip(citation.headings.length > 1 ? 1 : 0),
    ].join(' · ');
    final note = this.note;

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
        SoliplexSpacing.s1,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Citation ${citationBadgeNumber(citation, position)}',
            excludeSemantics: true,
            child: SoliplexBadge(
              label: Text('${citationBadgeNumber(citation, position)}'),
              intent: BadgeIntent.warning,
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (where.isNotEmpty)
                  Text(
                    where,
                    style: theme.textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  note ?? citation.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (count > 1) ...[
            IconButton(
              tooltip: 'Previous citation',
              icon: const Icon(Icons.chevron_left),
              onPressed: position == 0 ? null : () => onSelect(position - 1),
            ),
            Text(
              '${position + 1} / $count',
              style: theme.textTheme.labelMedium,
            ),
            IconButton(
              tooltip: 'Next citation',
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  position == count - 1 ? null : () => onSelect(position + 1),
            ),
          ],
        ],
      ),
    );
  }
}
