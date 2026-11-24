import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show CancelledException, NotFoundException;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../file_size.dart';
import '../markdown/launch_markdown_link.dart';
import '../reduced_url.dart';
import '../selectable_content.dart';
import 'pdf_document_view.dart';
import 'pdf_password_dialog.dart';
import 'pdf_source.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.pdf_viewer');

/// The largest file the viewer opens. A PDF is held in memory whole, once as
/// fetched bytes and again in PDFium, so past this a phone risks running out;
/// such a file is offered for download instead.
const pdfViewerSizeCapBytes = 50 * 1024 * 1024;

/// How many wrong passwords the viewer asks past before it gives up.
const _passwordAttempts = 3;

/// A PDF viewer: a header with the file's name, page, search, zoom and save
/// controls, the document, and — while text is selected — *Ask about this*.
///
/// Fills whatever it is given: a pane beside the conversation, a dialog, or
/// a page of its own. Opening another [source] replaces the document; a new
/// [initialPage] on the same one moves to it, and a new [passage] marks it
/// and moves to it.
class PdfViewerPane extends StatefulWidget {
  const PdfViewerPane({
    super.key,
    required this.source,
    required this.documentViewFactory,
    required this.onClose,
    this.initialPage = 1,
    this.passage,
    this.banner,
    this.onAskAbout,
    this.onSave,
    this.loadIndexedText,
    this.citedPages,
  });

  /// Narrower than this, the header's controls stop fitting.
  static const minWidth = 360.0;

  final PdfViewerSource source;
  final PdfDocumentViewFactory documentViewFactory;
  final VoidCallback onClose;
  final int initialPage;

  /// A passage to mark — a citation's — once the document is open. Null
  /// marks none.
  final PdfPassage? passage;

  /// Shown under the header, across the pane: what the passage is, and a
  /// way to step between passages.
  final Widget? banner;

  /// Receives the selected text when the user asks about it. Null hides
  /// *Ask about this* — where there is no conversation to ask in.
  final void Function(PdfSelectedText selection)? onAskAbout;

  /// Saves a fetched document to the device. Null hides Download.
  final Future<void> Function(Uint8List bytes, String filename)? onSave;

  /// Fetches the document's text as it was indexed, block by block: what
  /// the LLM can find in it, OCR included. Its blocks make a scanned page's
  /// paragraphs tappable, and *Show indexed text* frames them all. Null — the
  /// document was never indexed — offers neither.
  final Future<List<PdfTextBlock>> Function()? loadIndexedText;

  /// The pages the document's citations come from, 1-based: *Only cited
  /// pages*, on by default, shows just these. Null — not opened from a
  /// citation — offers no such option.
  final Set<int>? citedPages;

  @override
  State<PdfViewerPane> createState() => _PdfViewerPaneState();
}

sealed class _Phase {
  const _Phase();
}

final class _Fetching extends _Phase {
  const _Fetching();
}

final class _Ready extends _Phase {
  const _Ready({this.bytes, this.uri});

  final Uint8List? bytes;
  final Uri? uri;
}

final class _TooLarge extends _Phase {
  const _TooLarge(this.sizeBytes, {this.bytes});

  final int sizeBytes;
  final Uint8List? bytes;
}

enum _FailureKind { gone, retryable, external, notPdf, protected }

final class _Failed extends _Phase {
  const _Failed(this.kind, {this.bytes});

  final _FailureKind kind;

  /// What was fetched before the document failed to open, so it can still
  /// be saved.
  final Uint8List? bytes;
}

class _PdfViewerPaneState extends State<PdfViewerPane> {
  _Phase _phase = const _Fetching();

  /// Bumped on every load, so a fetch that finishes after the source changed
  /// is dropped, and a retry builds a fresh document view.
  var _generation = 0;
  PdfDocumentController? _document;
  var _passwordTries = 0;
  var _searching = false;
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'PDF search');

  /// The View menu's options. Only cited pages starts on; it goes off when
  /// the reader turns it off, or when a search match on a hidden page shows
  /// every page.
  var _onlyCited = true;
  var _showContext = false;
  var _showIndexed = false;

  /// The indexed text, once fetched, and the fetch while it runs; kept
  /// across a reload of the same document.
  List<PdfTextBlock>? _blocks;
  Future<List<PdfTextBlock>?>? _fetchingBlocks;

  /// Set when fetching the blocks on its own failed, so it is not tried
  /// again on every status change; turning on *Show indexed text* still
  /// does.
  var _blocksFailed = false;

  /// Stops watching the open document's status.
  void Function()? _stopWatching;

  /// False while [initState] runs, where the first load's opening phase is
  /// assigned rather than set: there is no build yet to schedule.
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _initialized = true;
  }

  void _setPhase(_Phase phase) {
    if (_initialized) {
      setState(() => _phase = phase);
    } else {
      _phase = phase;
    }
  }

  @override
  void didUpdateWidget(PdfViewerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.cacheKey != widget.source.cacheKey) {
      _closeSearch();
      _onlyCited = true;
      _blocks = null;
      _fetchingBlocks = null;
      _blocksFailed = false;
      unawaited(_load());
    } else {
      if (oldWidget.initialPage != widget.initialPage) {
        unawaited(_document?.goToPage(widget.initialPage));
      }
      final document = _document;
      if (document != null &&
          (oldWidget.passage != widget.passage ||
              !_sameSet(oldWidget.citedPages, widget.citedPages))) {
        document.showOnlyPages(_pagesToShow);
        if (oldWidget.passage != widget.passage) {
          unawaited(document.showPassage(_passageToShow));
        }
      }
    }
  }

  static bool _sameSet(Set<int>? a, Set<int>? b) => a == null
      ? b == null
      : b != null && a.length == b.length && a.containsAll(b);

  /// The pages *Only cited pages* shows: the citations', and the passage's
  /// own in case its boxes say more than the citation did; null shows all.
  Set<int>? get _pagesToShow {
    final cited = widget.citedPages;
    if (!_onlyCited || cited == null || cited.isEmpty) return null;
    return {...cited, ...?widget.passage?.anchor.map((box) => box.page)};
  }

  /// The passage as marked: without its context unless *Show context* is
  /// on — or unless context is all it has.
  PdfPassage? get _passageToShow {
    final passage = widget.passage;
    if (passage == null || _showContext || passage.anchor.isEmpty) {
      return passage;
    }
    return PdfPassage(anchor: passage.anchor);
  }

  /// Applies everything the pane decides to a document just opened, and
  /// follows its status from then on.
  void _onDocumentReady(PdfDocumentController document) {
    _stopWatching?.call();
    Set<int>? shown;
    _stopWatching = effect(() {
      final status = document.status.value;
      untracked(() {
        // Pages hidden a moment ago all show now, and the pane didn't ask:
        // a search went to a match on a hidden one.
        if (shown != null && status.onlyPages == null && _onlyCited) {
          setState(() => _onlyCited = false);
        }
        shown = status.onlyPages;
        if (status.textlessPages.isNotEmpty &&
            _blocks == null &&
            !_blocksFailed) {
          unawaited(_loadBlocks(quiet: true));
        }
      });
    });
    document.showOnlyPages(_pagesToShow);
    final passage = _passageToShow;
    if (passage != null) unawaited(document.showPassage(passage));
    final blocks = _blocks;
    if (blocks != null) document.showTextBlocks(blocks, framed: _showIndexed);
  }

  @override
  void dispose() {
    _stopWatching?.call();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final source = widget.source;
    _document = null;
    _passwordTries = 0;
    switch (source.load) {
      case PdfLoadUri(:final uri):
        _setPhase(_Ready(uri: uri));
      case PdfLoadBytes(:final fetch):
        final listed = source.sizeBytes;
        if (listed != null && listed > pdfViewerSizeCapBytes) {
          _setPhase(_TooLarge(listed));
          return;
        }
        _setPhase(const _Fetching());
        final Uint8List bytes;
        try {
          bytes = await fetch();
        } on CancelledException {
          return;
        } on Exception catch (error, stackTrace) {
          if (!mounted || generation != _generation) return;
          // The API client's exceptions carry status codes, hosts, paths
          // and the server's own reason, never a credential: the token
          // travels in a header the transport does not quote.
          _logger.warning(
            'Fetching a PDF failed',
            error: error,
            stackTrace: stackTrace,
            attributes: {'source': source.cacheKey},
          );
          _setPhase(
            _Failed(
              error is NotFoundException
                  ? _FailureKind.gone
                  : _FailureKind.retryable,
            ),
          );
          return;
        }
        if (!mounted || generation != _generation) return;
        _setPhase(
          bytes.length > pdfViewerSizeCapBytes
              ? _TooLarge(bytes.length, bytes: bytes)
              : _Ready(bytes: bytes),
        );
    }
  }

  Future<String?> _askPassword() async {
    if (_passwordTries >= _passwordAttempts || !mounted) return null;
    _passwordTries++;
    _logger.info(
      'PDF asked for a password',
      attributes: {'source': widget.source.cacheKey, 'try': _passwordTries},
    );
    return showPdfPasswordDialog(
      context,
      documentTitle: widget.source.title,
      retry: _passwordTries > 1,
    );
  }

  void _onLoadFailed(int generation, Object error, StackTrace? stackTrace) {
    if (!mounted || generation != _generation) return;
    final phase = _phase;
    final bytes = phase is _Ready ? phase.bytes : null;
    final kind = _passwordTries > 0
        ? _FailureKind.protected
        : bytes == null
            ? _FailureKind.external
            : _FailureKind.notPdf;
    if (bytes == null) {
      // A load from a link can fail with the link in its text; only the
      // shape of the failure is kept, beside the link reduced to its host
      // and path.
      final uri = phase is _Ready ? phase.uri : null;
      _logger.warning(
        'Opening a linked PDF failed',
        stackTrace: stackTrace,
        attributes: {
          'failure': describeFailure(error),
          if (uri != null) 'url': reducedUrl(uri.toString()),
        },
      );
    } else {
      // PDFium's errors name a stage and an error code, nothing from the
      // file.
      _logger.warning(
        'Opening a fetched PDF failed',
        error: error,
        stackTrace: stackTrace,
        attributes: {
          'source': widget.source.cacheKey,
          'bytes': bytes.length,
          'passwordTries': _passwordTries,
        },
      );
    }
    setState(() => _phase = _Failed(kind, bytes: bytes));
  }

  Future<void> _askAbout() async {
    final document = _document;
    final onAskAbout = widget.onAskAbout;
    if (document == null || onAskAbout == null) return;
    final result = await document.takeSelection();
    if (!mounted) return;
    switch (result) {
      case null:
        return;
      case PdfSelectionCopyForbidden():
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              "This PDF doesn't allow copying its text, so it can't be "
              'quoted.',
            ),
          ),
        );
      case final PdfSelectedText selection:
        onAskAbout(selection);
    }
  }

  /// The indexed text: fetched once, the fetch shared while it runs. Null
  /// when it can't be had — said in a SnackBar unless [quiet].
  Future<List<PdfTextBlock>?> _loadBlocks({required bool quiet}) {
    final held = _blocks;
    if (held != null) return Future.value(held);
    return _fetchingBlocks ??= _fetchBlocks(quiet: quiet);
  }

  Future<List<PdfTextBlock>?> _fetchBlocks({required bool quiet}) async {
    final load = widget.loadIndexedText;
    if (load == null) return null;
    final cacheKey = widget.source.cacheKey;
    try {
      final blocks = await load();
      if (!mounted || widget.source.cacheKey != cacheKey) return null;
      setState(() => _blocks = blocks);
      _document?.showTextBlocks(blocks, framed: _showIndexed);
      return blocks;
    } on CancelledException {
      return null;
    } on Exception catch (error, stackTrace) {
      // As in _load: the API client's errors carry no credential.
      _logger.warning(
        'Fetching the indexed text failed',
        error: error,
        stackTrace: stackTrace,
        attributes: {'source': cacheKey},
      );
      if (!mounted || widget.source.cacheKey != cacheKey) return null;
      _blocksFailed = true;
      if (!quiet) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't load the indexed text.")),
        );
      }
      return null;
    } finally {
      if (widget.source.cacheKey == cacheKey) _fetchingBlocks = null;
    }
  }

  void _toggleOnlyCited() {
    setState(() => _onlyCited = !_onlyCited);
    _document?.showOnlyPages(_pagesToShow);
  }

  void _toggleContext() {
    setState(() => _showContext = !_showContext);
    final document = _document;
    if (document != null) {
      unawaited(document.showPassage(_passageToShow, reveal: false));
    }
  }

  Future<void> _toggleIndexed() async {
    final showing = !_showIndexed;
    setState(() => _showIndexed = showing);
    if (!showing) {
      _document?.showTextBlocks(_blocks, framed: false);
      return;
    }
    final blocks = await _loadBlocks(quiet: false);
    if (!mounted) return;
    if (blocks == null) {
      setState(() => _showIndexed = false);
      return;
    }
    _document?.showTextBlocks(blocks, framed: _showIndexed);
  }

  /// The View menu's entries for what the document offers; empty when it
  /// offers none.
  List<_ViewOption> _viewOptions(PdfDocumentController document) => [
        if (widget.citedPages?.isNotEmpty ?? false)
          (
            label: 'Only cited pages',
            checked: document.status.value.onlyPages != null,
            onToggle: _toggleOnlyCited,
          ),
        if (widget.passage?.context.isNotEmpty ?? false)
          (
            label: 'Show context',
            checked: _showContext,
            onToggle: _toggleContext,
          ),
        if (widget.loadIndexedText != null)
          (
            label: 'Show indexed text',
            checked: _showIndexed,
            onToggle: () => unawaited(_toggleIndexed()),
          ),
      ];

  Future<void> _openTextBlock(PdfTextBlock block) async {
    final document = _document;
    final blocks = _blocks;
    if (document == null || blocks == null) return;
    document.showTextBlocks(blocks, selected: block, framed: _showIndexed);
    final onAskAbout = widget.onAskAbout;
    final asked = await showModalBottomSheet<PdfSelectedText>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OcrTextSheet(
        block: block,
        canAsk: onAskAbout != null,
      ),
    );
    if (!mounted) return;
    if (identical(_document, document)) {
      document.showTextBlocks(blocks, framed: _showIndexed);
    }
    if (asked != null) onAskAbout?.call(asked);
  }

  /// The bytes in hand, or fetched again — a file too large to view was
  /// never fetched.
  Future<void> _download() async {
    final onSave = widget.onSave;
    final load = widget.source.load;
    if (onSave == null || load is! PdfLoadBytes) return;
    final phase = _phase;
    final held = switch (phase) {
      _Ready(:final bytes) => bytes,
      _TooLarge(:final bytes) => bytes,
      _Failed(:final bytes) => bytes,
      _Fetching() => null,
    };
    try {
      await onSave(held ?? await load.fetch(), widget.source.title);
    } on CancelledException {
      return;
    } on Exception catch (error, stackTrace) {
      // As in _load: the API client's errors carry no credential.
      _logger.warning(
        'Saving a PDF failed',
        error: error,
        stackTrace: stackTrace,
        attributes: {'source': widget.source.cacheKey},
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text("Couldn't save ${widget.source.title}.")),
      );
    }
  }

  void _openExternally() {
    final load = widget.source.load;
    if (load is PdfLoadUri) unawaited(launchMarkdownLink(load.uri.toString()));
  }

  void _toggleSearch() {
    if (_searching) {
      _closeSearch();
    } else {
      setState(() => _searching = true);
      // Asked for rather than autofocused: autofocus yields to whatever
      // already holds focus in the scope — the composer, beside the chat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searching) _searchFocus.requestFocus();
      });
    }
  }

  void _closeSearch() {
    if (!_searching) return;
    _query.clear();
    _document?.search('');
    setState(() => _searching = false);
  }

  bool get _canDownload =>
      widget.onSave != null && widget.source.load is PdfLoadBytes;

  bool get _canOpenExternally => widget.source.load is PdfLoadUri;

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            source: widget.source,
            status: document?.status,
            searching: _searching,
            canSearch: document != null,
            onSearch: _toggleSearch,
            viewOptions: document == null || _viewOptions(document).isEmpty
                ? null
                : () => _viewOptions(document),
            onZoomIn: document == null ? null : () => document.zoomIn(),
            onZoomOut: document == null ? null : () => document.zoomOut(),
            onDownload: _canDownload ? _download : null,
            onOpenExternally: _canOpenExternally ? _openExternally : null,
            onClose: widget.onClose,
          ),
          if (document != null && _blocks != null)
            Watch(
              (context) => document.status.value.textlessPages.isEmpty
                  ? const SizedBox.shrink()
                  : const _OcrHint(),
            ),
          if (_searching && document != null)
            _SearchBar(
              query: _query,
              focusNode: _searchFocus,
              document: document,
            ),
          if (widget.banner case final banner?) ...[
            const Divider(height: 1),
            banner,
          ],
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final title = widget.source.title;
    return switch (_phase) {
      _Fetching() => _Message(
          leading: const CircularProgressIndicator(),
          title: 'Opening $title…',
        ),
      _TooLarge(:final sizeBytes) => _Message(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: 'Too large to open here',
          detail: '$title is ${formatFileSize(sizeBytes)}; the viewer opens '
              'files up to ${formatFileSize(pdfViewerSizeCapBytes)}.',
          actions: [
            if (_canDownload) _DownloadButton(onPressed: _download),
          ],
        ),
      _Failed(:final kind) => _buildFailure(kind),
      _Ready(:final bytes, :final uri) => _buildDocument(bytes, uri),
    };
  }

  Widget _buildFailure(_FailureKind kind) {
    final title = widget.source.title;
    final (heading, detail) = switch (kind) {
      _FailureKind.gone => (
          'This file is no longer available',
          '$title was removed or renamed.',
        ),
      _FailureKind.retryable => (
          "Couldn't load $title",
          'Check the connection and try again.',
        ),
      _FailureKind.external => (
          "Couldn't open this PDF here",
          'Its server may not allow opening it from this app. It can still '
              'be opened in the browser.',
        ),
      _FailureKind.notPdf => (
          "Couldn't open $title",
          'The file may be damaged, or not a PDF.',
        ),
      _FailureKind.protected => (
          '$title is password-protected',
          'It could not be opened without its password.',
        ),
    };
    return _Message(
      leading: Icon(Icons.error_outline, color: context.danger),
      title: heading,
      detail: detail,
      actions: [
        if (kind == _FailureKind.retryable)
          SoliplexButton.filled(
            onPressed: () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
            child: const Text('Retry'),
          ),
        if (kind == _FailureKind.protected)
          SoliplexButton.outlined(
            onPressed: () => unawaited(_load()),
            child: const Text('Try again'),
          ),
        if (kind == _FailureKind.external && _canOpenExternally)
          SoliplexButton.filled(
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new),
            child: const Text('Open in browser'),
          ),
        if ((kind == _FailureKind.notPdf || kind == _FailureKind.protected) &&
            _canDownload)
          _DownloadButton(onPressed: _download),
      ],
    );
  }

  Widget _buildDocument(Uint8List? bytes, Uri? uri) {
    final generation = _generation;
    final view = widget.documentViewFactory(
      PdfDocumentViewRequest(
        bytes: bytes,
        uri: uri,
        sourceName: widget.source.cacheKey,
        initialPage: widget.initialPage,
        passwordProvider: _askPassword,
        onReady: (document) {
          if (mounted && generation == _generation) {
            setState(() => _document = document);
            _onDocumentReady(document);
          }
        },
        onLoadFailed: (error, stackTrace) =>
            _onLoadFailed(generation, error, stackTrace),
        onAskAbout: widget.onAskAbout == null ? null : _askAbout,
        onTextBlockTap: (block) => unawaited(_openTextBlock(block)),
      ),
    );
    final document = _document;
    return Stack(
      children: [
        KeyedSubtree(key: ValueKey(generation), child: view),
        // Offered for as long as text is selected, so the action is there
        // without the context menu — which a mouse opens only on a right
        // click.
        if (document != null && widget.onAskAbout != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: SoliplexSpacing.s4,
            child: Watch(
              (context) => document.status.value.hasSelection
                  ? Center(
                      child: SoliplexButton.filled(
                        onPressed: () => unawaited(_askAbout()),
                        icon: const Icon(Icons.format_quote),
                        child: const Text('Ask about this'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

/// One entry of the View menu.
typedef _ViewOption = ({String label, bool checked, VoidCallback onToggle});

/// Says that the scanned pages' text is OCR, and how to reach it: nothing
/// on the page shows it, and a drag selects nothing there.
class _OcrHint extends StatelessWidget {
  const _OcrHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        0,
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: SoliplexSpacing.s4,
            color: color,
          ),
          const SizedBox(width: SoliplexSpacing.s1),
          Flexible(
            child: Text(
              'Scanned pages: tap a paragraph to read, copy or ask about its '
              'text',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.source,
    required this.status,
    required this.searching,
    required this.canSearch,
    required this.onSearch,
    required this.viewOptions,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onDownload,
    required this.onOpenExternally,
    required this.onClose,
  });

  final PdfViewerSource source;
  final ReadonlySignal<PdfViewStatus>? status;
  final bool searching;
  final bool canSearch;
  final VoidCallback onSearch;

  /// The View menu's entries, read as it opens; null hides the menu.
  final List<_ViewOption> Function()? viewOptions;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenExternally;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final status = this.status;
    final menu = <(String, IconData, VoidCallback)>[
      if (onZoomIn case final zoomIn?) ('Zoom in', Icons.zoom_in, zoomIn),
      if (onZoomOut case final zoomOut?) ('Zoom out', Icons.zoom_out, zoomOut),
      if (onDownload case final download?)
        ('Download', Icons.download_outlined, download),
      if (onOpenExternally case final open?)
        ('Open in browser', Icons.open_in_new, open),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
        SoliplexSpacing.s1,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selectable, as the app's other viewer titles are.
                SelectableContent(
                  child: Text(
                    source.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (status == null)
                  Text(
                    source.origin,
                    style: muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Watch((context) {
                    final s = status.value;
                    final page = s.pageNumber;
                    final count = s.pageCount;
                    final shown = s.onlyPages?.length;
                    return Text(
                      [
                        source.origin,
                        if (page != null && count != null)
                          'Page $page of $count',
                        if (shown != null)
                          '$shown cited ${shown == 1 ? 'page' : 'pages'} shown',
                      ].join(' · '),
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
              ],
            ),
          ),
          if (viewOptions case final options?)
            PopupMenuButton<VoidCallback>(
              tooltip: 'View',
              icon: const Icon(Icons.tune),
              onSelected: (toggle) => toggle(),
              itemBuilder: (context) => [
                for (final option in options())
                  CheckedPopupMenuItem(
                    value: option.onToggle,
                    checked: option.checked,
                    child: Text(option.label),
                  ),
              ],
            ),
          IconButton(
            tooltip: searching ? 'Close search' : 'Search in document',
            isSelected: searching,
            icon: const Icon(Icons.search),
            onPressed: canSearch ? onSearch : null,
          ),
          if (menu.isNotEmpty)
            PopupMenuButton<VoidCallback>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                for (final (label, icon, action) in menu)
                  PopupMenuItem(
                    value: action,
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.query,
    required this.focusNode,
    required this.document,
  });

  final TextEditingController query;
  final FocusNode focusNode;
  final PdfDocumentController document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        0,
        SoliplexSpacing.s1,
        SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: SoliplexInput(
              controller: query,
              focusNode: focusNode,
              hintText: 'Search in document',
              leadingIcon: const Icon(Icons.search),
              onChanged: document.search,
              onSubmitted: (_) => unawaited(document.nextMatch()),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          // Rebuilt by the query as well as the document: "No matches"
          // depends on whether anything has been typed.
          ListenableBuilder(
            listenable: query,
            builder: (context, _) => Watch((context) {
              final s = document.status.value;
              final hasMatches = s.matchCount > 0;
              final label = hasMatches
                  ? '${(s.currentMatch ?? 0) + 1} of ${s.matchCount}'
                  : s.searching
                      ? 'Searching…'
                      : query.text.trim().isEmpty
                          ? ''
                          : 'No matches';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  IconButton(
                    tooltip: 'Previous match',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: hasMatches
                        ? () => unawaited(document.previousMatch())
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Next match',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: hasMatches
                        ? () => unawaited(document.nextMatch())
                        : null,
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.leading,
    required this.title,
    this.detail,
    this.actions = const [],
  });

  final Widget leading;
  final String title;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SoliplexSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(height: SoliplexSpacing.s3),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (detail case final detail?) ...[
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: SoliplexSpacing.s4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: SoliplexSpacing.s2,
                runSpacing: SoliplexSpacing.s2,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => SoliplexButton.outlined(
        onPressed: () => unawaited(onPressed()),
        icon: const Icon(Icons.download_outlined),
        child: const Text('Download'),
      );
}

/// A block of OCR text, to read, select part of, copy, or ask about. Pops
/// with the text to ask about, when asked.
class _OcrTextSheet extends StatefulWidget {
  const _OcrTextSheet({required this.block, required this.canAsk});

  final PdfTextBlock block;
  final bool canAsk;

  @override
  State<_OcrTextSheet> createState() => _OcrTextSheetState();
}

class _OcrTextSheetState extends State<_OcrTextSheet> {
  var _selection = '';

  /// The selection, or the whole block when nothing is selected, whitespace
  /// collapsed as a selection on the page is.
  String get _text =>
      (_selection.trim().isEmpty ? widget.block.text : _selection)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: _text));
    messenger?.showSnackBar(const SnackBar(content: Text('Copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = widget.block.box.page;
    final text = widget.block.text;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SoliplexSpacing.s4,
          0,
          SoliplexSpacing.s4,
          SoliplexSpacing.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('OCR text, p. $page', style: theme.textTheme.titleSmall),
            Text(
              'Read from the scan; it may contain recognition errors.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodyMedium,
                  onSelectionChanged: (selection, _) => setState(
                    () => _selection =
                        selection.isCollapsed ? '' : selection.textInside(text),
                  ),
                ),
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: SoliplexSpacing.s2,
              runSpacing: SoliplexSpacing.s2,
              children: [
                SoliplexButton.outlined(
                  onPressed: () => unawaited(_copy()),
                  icon: const Icon(Icons.copy_outlined),
                  child: Text(
                      _selection.trim().isEmpty ? 'Copy' : 'Copy selection'),
                ),
                if (widget.canAsk)
                  SoliplexButton.filled(
                    onPressed: () => Navigator.of(context).pop(
                      PdfSelectedText(text: _text, pageNumber: page),
                    ),
                    icon: const Icon(Icons.format_quote),
                    child: const Text('Ask about this'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
