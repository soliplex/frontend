import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show NotFoundException, SoliplexApi, SourceReference, isRetryable;
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

  /// Opens the page images of the chunk [source] cites, carrying every field
  /// of the citation the page reads.
  static Future<void> showCitation({
    required BuildContext context,
    required SoliplexApi api,
    required String roomId,
    required SourceReference source,
  }) =>
      _present(
        context,
        (useDialogLayout) => ChunkVisualizationPage(
          api: api,
          roomId: roomId,
          chunkId: source.chunkId,
          documentTitle: source.displayTitle,
          pageNumbers: source.pageNumbers,
          useDialogLayout: useDialogLayout,
          docItemRefs: source.docItemRefs,
          chunkDocItemRefs: source.chunkDocItemRefs,
          chunkPageNumbers: source.chunkPageNumbers,
          database: source.database,
        ),
      );

  /// Opens the pages a chunk looked up by its id alone is drawn on. Nothing
  /// else about it is known, so the title shows the id, the backend asks each
  /// database until one holds it, and the page names the one that did when
  /// the backend reports it.
  static Future<void> showChunk({
    required BuildContext context,
    required SoliplexApi api,
    required String roomId,
    required String chunkId,
  }) =>
      _present(
        context,
        (useDialogLayout) => ChunkVisualizationPage(
          api: api,
          roomId: roomId,
          chunkId: chunkId,
          pageNumbers: const [],
          useDialogLayout: useDialogLayout,
          database: null,
        ),
      );

  static Future<void> _present(
    BuildContext context,
    ChunkVisualizationPage Function(bool useDialogLayout) build,
  ) {
    final useDialog =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
    final child = build(useDialog);

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

/// Where one view of the page stands: its fetch in flight, its pages and the
/// database they came from, or the failure that ended its fetch.
sealed class _ViewLoad {
  const _ViewLoad();
}

final class _Loading extends _ViewLoad {
  const _Loading();
}

final class _Loaded extends _ViewLoad {
  const _Loaded(this.pages, this.database);

  final List<PageImage> pages;

  /// The database the backend found the chunk in. Null when the response
  /// names none.
  final String? database;
}

final class _Failed extends _ViewLoad {
  const _Failed(this.error);

  final Object error;
}

class _ChunkVisualizationPageState extends State<ChunkVisualizationPage> {
  // Each view's load, keyed by whether it sends the refs, kept for the life
  // of the page so switching back shows the earlier result without a request.
  final _views = <bool, _ViewLoad>{};

  // Whether the request sends the citation's refs. Off by default, so refs
  // leave the client only after the user asks for the context.
  bool _showContext = false;

  @override
  void initState() {
    super.initState();
    _fetch(sendRefs: _showContext);
  }

  // A view is fetched when first shown and on retry, which is offered only
  // once its fetch has failed, so no view has two fetches in flight.
  void _fetch({required bool sendRefs}) {
    _views[sendRefs] = const _Loading();
    _fetchAndDecode(sendRefs: sendRefs).then(
      (load) => _settle(sendRefs, load),
      onError: (Object error) => _settle(sendRefs, _Failed(error)),
    );
  }

  void _settle(bool sendRefs, _ViewLoad load) {
    if (!mounted) return;
    setState(() => _views[sendRefs] = load);
  }

  Future<_Loaded> _fetchAndDecode({required bool sendRefs}) async {
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
        'database': widget.database,
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
          'database': viz.database,
        },
      );
      return _Loaded(
        viz.imagesBase64.map(_decodePageImage).toList(),
        viz.database,
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
        attributes: {'failure': describeFailure(error)},
        stackTrace: stack,
      );
      return PageImageBroken(reason: error.message);
    }
  }

  void _retry() => setState(() => _fetch(sendRefs: _showContext));

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

  Widget _buildContent(BuildContext context) => switch (_views[_showContext]!) {
        _Loading() => const Center(child: CircularProgressIndicator()),
        // The backend answers 404 when it draws nothing for the view (or
        // holds no such chunk) — the same outcome as an empty result.
        _Failed(error: NotFoundException()) => _buildNoImages(context),
        _Failed(:final error) => _buildError(context, error),
        _Loaded(:final pages) => _buildLoaded(context, pages),
      };

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
  // sending the refs adds, drawn as context. When the citation does not
  // report its chunk's refs, `chunkDocItemRefs` is empty, so every ref counts
  // as outside and the switch shows.
  bool get _quotesBeyondChunk =>
      widget.docItemRefs.any((ref) => !widget.chunkDocItemRefs.contains(ref));

  // The database that answered, shown only when the page named none. The
  // backend then takes the first database holding the id, and chunk ids
  // repeat between copies of a database. Given a database, the backend asks
  // only that one, so naming it again would tell the user nothing.
  String? get _answeringDatabase => switch (_views[_showContext]) {
        _Loaded(:final database) when widget.database == null => database,
        _ => null,
      };

  Widget _buildBody(BuildContext context) {
    final answeringDatabase = _answeringDatabase;
    return Column(
      children: [
        if (_quotesBeyondChunk)
          _buildContextSwitch()
        else if (widget.docItemRefs.isNotEmpty)
          _buildNote(
            context,
            'The answer used no context beyond this passage.',
          ),
        if (answeringDatabase != null)
          _buildNote(context, 'Database: $answeringDatabase'),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  // Shared by the context switch and the notes, so every row above the pages
  // sits at one inset.
  static const _contextRowPadding =
      EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4);

  Widget _buildContextSwitch() {
    return SwitchListTile(
      title: const Text('Show context the answer used'),
      value: _showContext,
      onChanged: (value) => setState(() {
        _showContext = value;
        if (!_views.containsKey(value)) _fetch(sendRefs: value);
      }),
      contentPadding: _contextRowPadding,
    );
  }

  Widget _buildNote(BuildContext context, String text) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        text,
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
          if (isRetryable(error)) ...[
            const SizedBox(height: SoliplexSpacing.s4),
            SoliplexButton.filled(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  // The off view draws only the chunk's own items; when they give no page
  // image, the cited passage may still have one.
  Widget _buildNoImages(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No page images available'),
            if (!_showContext && _quotesBeyondChunk) ...[
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                'Try “Show context the answer used” above to see the cited '
                'passage.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
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
    if (pages.isEmpty) return _buildNoImages(context);
    return PagedZoomableImages(
      // Keyed by view: the two can differ in page count, so switching views
      // starts the pager at its first page, unrotated.
      key: ValueKey(_showContext),
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
