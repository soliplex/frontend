import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_design/soliplex_design.dart';
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
    required this.documentTitle,
    required this.pageNumbers,
    required this.useDialogLayout,
    this.docItemRefs = const [],
  });

  final SoliplexApi api;
  final String roomId;
  final String chunkId;
  final String documentTitle;
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
    required String documentTitle,
    required List<int> pageNumbers,
    List<String> docItemRefs = const [],
  }) {
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = ChunkVisualizationPage(
      api: api,
      roomId: roomId,
      chunkId: chunkId,
      documentTitle: documentTitle,
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

class _ChunkVisualizationPageState extends State<ChunkVisualizationPage> {
  late Future<List<PageImage>> _future;
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

  Future<List<PageImage>> _fetchAndDecode() async {
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
      return viz.imagesBase64.map(_decodePageImage).toList();
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
    return FutureBuilder<List<PageImage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!);
        }
        return _buildImages(context, snapshot.data ?? const []);
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
        title: Text(widget.documentTitle),
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
              widget.documentTitle,
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

  Widget _buildImages(BuildContext context, List<PageImage> pages) {
    if (pages.isEmpty) {
      return const Center(child: Text('No page images available'));
    }

    return PagedZoomableImages(
      key: ValueKey(_reloadNonce),
      itemCount: pages.length,
      pageBuilder: (context, index, rotation) => _buildPageImage(
          pages[index], rotation.quarterTurns, rotation.onRotate),
      footerBuilder: (context, index) => Text(
        _pageLabel(index, pages.length),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      dotLabelForIndex: (i) => 'Page ${i + 1}',
    );
  }
}
