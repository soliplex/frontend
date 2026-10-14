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
    required this.pageNumbers,
    required this.useDialogLayout,
    this.documentTitle,
    this.docItemRefs = const [],
    this.chunkDocItemRefs = const [],
    this.chunkPageNumbers = const [],
    required this.database,
  });

  final SoliplexApi api;
  final String roomId;
  final String chunkId;

  /// The document's display name for the title bar, when the caller knows it
  /// (citations). Null for a bare chunk-id lookup, where the title falls back
  /// to the chunk id so the user sees the id they looked up.
  final String? documentTitle;
  final List<int> pageNumbers;
  final bool useDialogLayout;

  /// The citation's doc-item refs. Sent to the backend only once the user
  /// turns on the context switch, so the highlight then covers the passage
  /// the citation quoted rather than just the matched chunk.
  final List<String> docItemRefs;

  /// The doc-item refs of the cited chunk itself — what the backend draws as
  /// the matched chunk. Empty when the citation does not report them.
  final List<String> chunkDocItemRefs;

  /// The pages the cited chunk itself appears on, where [pageNumbers] covers
  /// the whole cited passage. Empty when the citation does not report them.
  final List<int> chunkPageNumbers;

  /// The RAG database the chunk came from, as its citation reports it, so
  /// the backend asks that one rather than the first holding the id. Null
  /// for a bare chunk-id lookup, or a citation that names none.
  final String? database;

  static Future<void> show({
    required BuildContext context,
    required SoliplexApi api,
    required String roomId,
    required String chunkId,
    required List<int> pageNumbers,
    String? documentTitle,
    List<String> docItemRefs = const [],
    List<String> chunkDocItemRefs = const [],
    List<int> chunkPageNumbers = const [],
    required String? database,
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
      chunkDocItemRefs: chunkDocItemRefs,
      chunkPageNumbers: chunkPageNumbers,
      database: database,
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
  // Each mode's fetch, keyed by whether it sends the refs, kept for the life
  // of the page so switching back shows the earlier result without a request.
  final _futures = <bool, Future<List<PageImage>>>{};
  // Bumped on retry so the pager remounts with fresh rotation/page state; the
  // pager key also carries the mode, as the two can differ in page count.
  int _reloadNonce = 0;

  // Whether the request sends the citation's refs. Off by default, so refs
  // leave the client only after the user asks for the context.
  bool _showContext = false;

  Future<List<PageImage>> get _future => _futures[_showContext]!;

  @override
  void initState() {
    super.initState();
    _loadVisualization();
  }

  void _loadVisualization() {
    _futures[_showContext] ??= _fetchSelectedMode();
  }

  // A mode's fetch can fail while nothing listens — before the next frame
  // builds its FutureBuilder, or after the user switched to the other mode.
  // The fetch logs its own failure and the FutureBuilder still receives the
  // error once it listens, so mark it handled rather than let it surface as
  // uncaught.
  Future<List<PageImage>> _fetchSelectedMode() =>
      _fetchAndDecode(sendRefs: _showContext)..ignore();

  Future<List<PageImage>> _fetchAndDecode({required bool sendRefs}) async {
    final refs = sendRefs ? widget.docItemRefs : const <String>[];
    final refCount = refs.length;
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
        refs: refs,
        database: widget.database,
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
        attributes: {'failure': describeFailure(error)},
        stackTrace: stack,
      );
      return PageImageBroken(reason: error.message);
    }
  }

  void _retry() {
    setState(() {
      _reloadNonce++;
      _futures[_showContext] = _fetchSelectedMode();
    });
  }

  String _pageLabel(int index, int total) {
    // The backend returns one image per page holding a drawn item: with the
    // refs, the cited passage's pages; without, only the chunk's own. A
    // citation with no refs was never expanded, so its pages are the chunk's.
    final pn = _showContext || widget.docItemRefs.isEmpty
        ? widget.pageNumbers
        : widget.chunkPageNumbers;
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
        return _buildLoaded(context, snapshot.data!);
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
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentTitle ?? widget.chunkId),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
      // Without SafeArea, the system gesture inset (iOS home indicator,
      // Android nav bar) sits on top of the dots row at the bottom of
      // the page strip — making them effectively untappable.
      body: SafeArea(top: false, child: _buildBody(context)),
    );
  }

  // Whether the citation quotes items outside its chunk: the only ones that
  // sending the refs adds, drawn as context. Chunk refs the citation does not
  // report are empty, so every ref counts as outside and the switch shows.
  bool get _quotesBeyondChunk =>
      widget.docItemRefs.any((ref) => !widget.chunkDocItemRefs.contains(ref));

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        if (_quotesBeyondChunk)
          _buildContextSwitch()
        else if (widget.docItemRefs.isNotEmpty)
          _buildNoContextNote(context),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  // Shared by the switch and the note that replaces it: both are one-line list
  // tiles, so with the same padding the note takes the switch row's inset and
  // height.
  static const _contextRowPadding =
      EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4);

  Widget _buildContextSwitch() {
    return SwitchListTile(
      title: const Text('Show context the answer used'),
      value: _showContext,
      onChanged: (value) => setState(() {
        _showContext = value;
        _loadVisualization();
      }),
      contentPadding: _contextRowPadding,
    );
  }

  Widget _buildNoContextNote(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        'The answer used no context beyond this passage.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      contentPadding: _contextRowPadding,
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
              widget.documentTitle ?? widget.chunkId,
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

  Widget _buildLoaded(BuildContext context, List<PageImage> pages) {
    if (pages.isEmpty) {
      return const Center(child: Text('No page images available'));
    }
    return PagedZoomableImages(
      key: ValueKey((_showContext, _reloadNonce)),
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
    );
  }
}
