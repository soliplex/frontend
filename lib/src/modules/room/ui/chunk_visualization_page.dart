import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../../../shared/copy_button.dart';
import '../../../shared/failed_image.dart';
import '../../../shared/zoomable_image.dart';
import 'paged_zoomable_images.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.chunk_visualization');

@visibleForTesting
sealed class PageImage {
  const PageImage();
}

/// A page whose base64 payload decoded to bytes. Codec-time failures (bytes
/// were valid base64 but not a valid image) are not represented here — they
/// happen during paint and are surfaced by [ZoomableImage]'s decode fallback.
@visibleForTesting
final class PageImageDecoded extends PageImage {
  const PageImageDecoded({required this.bytes});

  final Uint8List bytes;
}

/// A page whose base64 payload could not be decoded. Codec-time failures
/// (bytes were valid base64 but not a valid image) are not represented here —
/// they happen during paint and are surfaced by [ZoomableImage]'s decode
/// fallback.
@visibleForTesting
final class PageImageBroken extends PageImage {
  const PageImageBroken({required this.reason});

  final String reason;
}

class ChunkVisualizationPage extends StatefulWidget {
  const ChunkVisualizationPage({
    super.key,
    required this.api,
    required this.roomId,
    required this.chunkId,
    required this.pageNumbers,
    required this.useDialogLayout,
    this.documentTitle,
    this.documentUri,
    this.docItemRefs = const [],
  });

  final SoliplexApi api;
  final String roomId;
  final String chunkId;

  /// The document's display name for the title bar, when the caller knows it
  /// (citations). Null for a bare chunk-id lookup, where the title falls back
  /// to a neutral label.
  final String? documentTitle;

  /// The document uri shown in the detail block, when the caller knows it
  /// (citations). Null for a bare chunk-id lookup, where the detail block
  /// falls back to the uri returned by the fetch (which may itself be absent).
  final String? documentUri;
  final List<int> pageNumbers;
  final bool useDialogLayout;

  /// The citation's doc-item refs, sent to the backend so the highlight
  /// matches the cited content instead of re-expanding.
  final List<String> docItemRefs;

  static Future<void> show({
    required BuildContext context,
    required SoliplexApi api,
    required String roomId,
    required String chunkId,
    required List<int> pageNumbers,
    String? documentTitle,
    String? documentUri,
    List<String> docItemRefs = const [],
  }) {
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = ChunkVisualizationPage(
      api: api,
      roomId: roomId,
      chunkId: chunkId,
      documentTitle: documentTitle,
      documentUri: documentUri,
      pageNumbers: pageNumbers,
      useDialogLayout: useDialog,
      docItemRefs: docItemRefs,
    );

    if (useDialog) {
      // Zero-duration transition — the default fade adds a visible
      // flash when the user is expecting an immediate jump from the
      // citation to its rendered pages.
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => child,
      );
    }

    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => child,
      ),
    );
  }

  @override
  State<ChunkVisualizationPage> createState() => _ChunkVisualizationPageState();
}

/// The decoded pages plus the document uri the backend reported for the
/// chunk, surfaced together so the detail block can show provenance.
typedef _VizResult = ({List<PageImage> pages, String? documentUri});

class _ChunkVisualizationPageState extends State<ChunkVisualizationPage> {
  /// Title shown when the caller has no document name (bare chunk-id lookup).
  static const _fallbackTitle = 'Chunk preview';

  late Future<_VizResult> _future;
  // Bumped on retry so the pager remounts with fresh rotation/page state.
  int _reloadNonce = 0;

  @override
  void initState() {
    super.initState();
    _loadVisualization();
  }

  void _loadVisualization() {
    _future = _fetchAndDecode();
  }

  Future<_VizResult> _fetchAndDecode() async {
    final refCount = widget.docItemRefs.length;
    final grounded = refCount > 0;
    _logger.debug(
      'fetching chunk visualization',
      attributes: {
        'roomId': widget.roomId,
        'chunkId': widget.chunkId,
        'refCount': refCount,
        'grounded': grounded,
      },
    );
    try {
      final viz = await widget.api.getChunkVisualization(
        widget.roomId,
        widget.chunkId,
        refs: widget.docItemRefs,
      );
      _logger.debug(
        'chunk visualization fetched',
        attributes: {
          'chunkId': widget.chunkId,
          'refCount': refCount,
          'grounded': grounded,
          'pageCount': viz.imagesBase64.length,
        },
      );
      return (
        pages: viz.imagesBase64.map(_decodePageImage).toList(),
        documentUri: viz.documentUri,
      );
    } catch (error, stack) {
      _logger.error(
        'chunk visualization fetch failed',
        error: error,
        stackTrace: stack,
        attributes: {
          'errorType': error.runtimeType.toString(),
          'chunkId': widget.chunkId,
          'refCount': refCount,
          'grounded': grounded,
        },
      );
      rethrow;
    }
  }

  /// Decodes one entry from `imagesBase64`. Returns a [PageImageDecoded] on
  /// success or a [PageImageBroken] on FormatException so a single corrupt
  /// image doesn't collapse the entire visualization.
  static PageImage _decodePageImage(String b64) {
    try {
      return PageImageDecoded(bytes: base64Decode(b64));
    } on FormatException catch (error, stack) {
      _logger.warning(
        'chunk image base64 decode failed',
        error: error,
        stackTrace: stack,
      );
      return PageImageBroken(reason: error.message);
    }
  }

  void _retry() {
    setState(() {
      _reloadNonce++;
      _loadVisualization();
    });
  }

  String _pageLabel(int index, int total) {
    final pn = widget.pageNumbers;
    if (pn.isEmpty) return 'Image ${index + 1} of $total';
    // Chunk spans more pages than images — show combined label.
    if (pn.length > total && total == 1) {
      return 'Pages ${pn.first}–${pn.last}';
    }
    if (index < pn.length) return 'Page ${pn[index]}';
    return 'Image ${index + 1} of $total';
  }

  Widget _buildContent(BuildContext context) {
    return FutureBuilder<_VizResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!);
        }
        final result = snapshot.data!;
        return _buildLoaded(context, result.pages, result.documentUri);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useDialogLayout) {
      return Dialog(
        insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 800,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTitleBar(context),
              Expanded(child: _buildContent(context)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentTitle ?? _fallbackTitle),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
      // Without SafeArea, the system gesture inset (iOS home indicator,
      // Android nav bar) sits on top of the dots row at the bottom of
      // the page strip — making them effectively untappable.
      body: SafeArea(top: false, child: _buildContent(context)),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.documentTitle ?? _fallbackTitle,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Failed to load visualization',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          _detailField(context, 'chunk id', widget.chunkId),
          const SizedBox(height: SoliplexSpacing.s4),
          SoliplexButton.filled(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// A labelled metadata field with a copy button and a selectable monospace
  /// value, copyable in one tap or selectable directly. Used for the chunk id
  /// (detail block and error state) and the document uri (detail block only).
  Widget _detailField(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(width: SoliplexSpacing.s1),
            // Match the copy icon to the label's type-scale size so the two
            // read as one line rather than the icon overpowering the label.
            CopyButton(
              text: value,
              tooltip: 'Copy $label',
              iconSize: labelStyle?.fontSize ?? 12,
            ),
          ],
        ),
        SelectableText(
          value,
          style: context.monospaceOn(theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, String? fetchedDocumentUri) {
    // Prefer the caller's uri (citations), treating empty as absent so a blank
    // citation uri doesn't shadow a real fetched one; fall back to the fetched
    // uri for a bare chunk-id lookup. Absent in both (null/empty) → the row is
    // hidden and only the chunk id shows.
    final callerUri = widget.documentUri;
    final document = (callerUri != null && callerUri.isNotEmpty)
        ? callerUri
        : fetchedDocumentUri;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        0,
        SoliplexSpacing.s4,
        SoliplexSpacing.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Theme.of(context).colorScheme.outline),
          _detailField(context, 'chunk id', widget.chunkId),
          if (document != null && document.isNotEmpty) ...[
            const SizedBox(height: SoliplexSpacing.s2),
            _detailField(context, 'document', document),
          ],
        ],
      ),
    );
  }

  Widget _buildPageImage(
    PageImage page,
    int rotationQuarterTurns,
    VoidCallback onRotate,
  ) {
    return switch (page) {
      PageImageBroken(:final reason) => Center(
          // FormatException messages are usually short but uncapped; bound
          // the displayed reason so a long message doesn't blow out the
          // placeholder.
          child: FailedImage(
            label: 'Page image failed to decode: '
                '${reason.length <= 80 ? reason : '${reason.substring(0, 80)}…'}',
          ),
        ),
      PageImageDecoded(:final bytes) => ZoomableImage.controlledRotation(
          bytes: bytes,
          rotationQuarterTurns: rotationQuarterTurns,
          onRotate: onRotate,
          decodeFailureChild:
              const FailedImage(label: 'Page image failed to render'),
        ),
    };
  }

  Widget _buildLoaded(
    BuildContext context,
    List<PageImage> pages,
    String? documentUri,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: pages.isEmpty
              ? const Center(child: Text('No page images available'))
              : PagedZoomableImages(
                  key: ValueKey(_reloadNonce),
                  itemCount: pages.length,
                  pageBuilder: (context, index, rotation) => _buildPageImage(
                    pages[index],
                    rotation.quarterTurns,
                    rotation.onRotate,
                  ),
                  footerBuilder: (context, index) => Text(
                    _pageLabel(index, pages.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  dotLabelForIndex: (i) => 'Page ${i + 1}',
                ),
        ),
        _buildDetails(context, documentUri),
      ],
    );
  }
}
