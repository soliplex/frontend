import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show NotFoundException;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../download_feedback.dart';
import '../file_size.dart';
import '../markdown/launch_markdown_link.dart';
import '../notice_pill.dart';
import '../progress_ring.dart';
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

/// A file's download as the viewer shows and starts it. Its state must be
/// owned by whoever opened the viewer, so that a download outlives the
/// viewer.
class PdfDownload {
  const PdfDownload({required this.state, required this.start});

  /// Where the download stands. It must read a signal, so the viewer's
  /// controls follow it inside a `Watch`, and report each failed attempt as
  /// a new [DownloadFailed]: the viewer hides a dismissed failure by
  /// identity.
  final DownloadFeedbackState Function() state;

  /// Starts a download, asked from [context] inside the viewer: anything it
  /// shows first, such as a confirm, opens over the viewer. The viewer calls
  /// it only while the state says one may start.
  final void Function(BuildContext context) start;
}

/// A PDF viewer: a header with the file's name, page, search, zoom and
/// download controls, the document, and — while text is selected —
/// *Ask about this*.
///
/// Fills whatever it is given: a pane beside the conversation, a dialog, or
/// a page of its own. Opening another [source] replaces the document; a new
/// [initialPage] on the same one moves to it.
class PdfViewerPane extends StatefulWidget {
  const PdfViewerPane({
    super.key,
    required this.source,
    required this.documentViewFactory,
    required this.onClose,
    this.initialPage = 1,
    this.onAskAbout,
    this.download,
  });

  /// Narrower than this, the header's controls stop fitting.
  static const minWidth = 360.0;

  final PdfViewerSource source;
  final PdfDocumentViewFactory documentViewFactory;
  final VoidCallback onClose;
  final int initialPage;

  /// Receives the selected text when the user asks about it. Null hides
  /// *Ask about this* — where there is no conversation to ask in.
  final void Function(PdfSelectedText selection)? onAskAbout;

  /// The file's download, behind the viewer's Download controls and the
  /// notice of a failed one. Null hides them, as does a file that cannot be
  /// fetched at all (gone, or an address the client refuses).
  final PdfDownload? download;

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
  const _TooLarge(this.sizeBytes);

  final int sizeBytes;
}

enum _FailureKind { gone, badAddress, retryable, external, notPdf, protected }

final class _Failed extends _Phase {
  const _Failed(this.kind);

  final _FailureKind kind;
}

class _PdfViewerPaneState extends State<PdfViewerPane> {
  _Phase _phase = const _Fetching();

  /// Bumped on every load, so a fetch that finishes after the source changed
  /// is dropped, and a retry builds a fresh document view.
  var _generation = 0;
  PdfDocumentController? _document;
  var _passwordTries = 0;
  var _searching = false;

  /// The failure last dismissed from the notice, hidden by identity while
  /// this viewer lives. Each failed attempt is a new instance, so the next
  /// failure shows; dismissing another file's failure, or reopening the
  /// viewer, shows this one again.
  DownloadFailed? _dismissedFailure;
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'PDF search');

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
      unawaited(_load());
    } else if (oldWidget.initialPage != widget.initialPage) {
      unawaited(_document?.goToPage(widget.initialPage));
    }
  }

  @override
  void dispose() {
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
        } on Object catch (error, stackTrace) {
          if (!mounted || generation != _generation) return;
          final attributes = {'source': source.cacheKey};
          if (error is Exception || error is ArgumentError) {
            // The fetches pdf_targets.dart builds call the API client: its
            // exceptions carry status codes, hosts, paths and the server's
            // own reason, as the token travels in a header the transport
            // does not quote, and its ArgumentError holds the id, name or
            // path it refused, which `source` names anyway; a RangeError,
            // also an ArgumentError, holds only a number. None is a
            // credential.
            _logger.warning(
              'Fetching a PDF failed',
              error: error,
              stackTrace: stackTrace,
              attributes: attributes,
            );
          } else {
            // Anything else, an Error above all, holds text written by
            // whoever threw it, which nothing here can vouch for; only its
            // type is kept.
            _logger.warning(
              'Fetching a PDF failed',
              stackTrace: stackTrace,
              attributes: {...attributes, 'failure': describeFailure(error)},
            );
          }
          _setPhase(
            _Failed(
              switch (error) {
                NotFoundException() => _FailureKind.gone,
                // The API client refuses an address it cannot request — an
                // empty ID, or a file name or path with a segment it will not
                // send — before sending anything; asking again cannot help. A
                // RangeError is an ArgumentError too, but means a bug, not an
                // address, so it takes the default.
                RangeError() => _FailureKind.retryable,
                ArgumentError() => _FailureKind.badAddress,
                _ => _FailureKind.retryable,
              },
            ),
          );
          return;
        }
        if (!mounted || generation != _generation) return;
        _setPhase(
          bytes.length > pdfViewerSizeCapBytes
              ? _TooLarge(bytes.length)
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
    setState(() => _phase = _Failed(kind));
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

  /// Download, where there is one and the file can be fetched at all.
  PdfDownload? get _download => switch (_phase) {
        _Failed(kind: _FailureKind.gone || _FailureKind.badAddress) => null,
        _ => widget.download,
      };

  /// Whether the page itself offers Download, with a failure's reason under
  /// it, so the notice above the document would say it twice.
  bool get _pageOffersDownload => switch (_phase) {
        _TooLarge() ||
        _Failed(kind: _FailureKind.notPdf || _FailureKind.protected) =>
          true,
        _ => false,
      };

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
            onZoomIn: document == null ? null : () => document.zoomIn(),
            onZoomOut: document == null ? null : () => document.zoomOut(),
            download: _download,
            onOpenExternally: _canOpenExternally ? _openExternally : null,
            onClose: widget.onClose,
          ),
          if (_searching && document != null)
            _SearchBar(
              query: _query,
              focusNode: _searchFocus,
              document: document,
            ),
          if (_download case final download? when !_pageOffersDownload)
            _DownloadFailureNotice(
              key: ValueKey(widget.source.cacheKey),
              download: download,
              dismissed: _dismissedFailure,
              onDismiss: (failure) =>
                  setState(() => _dismissedFailure = failure),
            ),
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
            if (_download case final download?)
              _DownloadButton(
                key: ValueKey(widget.source.cacheKey),
                download: download,
              ),
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
      _FailureKind.badAddress => (
          "Couldn't open $title",
          "Its address isn't one this app can request.",
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
        if (kind == _FailureKind.notPdf || kind == _FailureKind.protected)
          if (_download case final download?)
            // Unkeyed: opening another file always replaces this page, so no
            // other file's download reaches this button.
            _DownloadButton(download: download),
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
          }
        },
        onLoadFailed: (error, stackTrace) =>
            _onLoadFailed(generation, error, stackTrace),
        onAskAbout: widget.onAskAbout == null ? null : _askAbout,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.source,
    required this.status,
    required this.searching,
    required this.canSearch,
    required this.onSearch,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.download,
    required this.onOpenExternally,
    required this.onClose,
  });

  final PdfViewerSource source;
  final ReadonlySignal<PdfViewStatus>? status;
  final bool searching;
  final bool canSearch;
  final VoidCallback onSearch;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final PdfDownload? download;
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
                    return Text(
                      [
                        source.origin,
                        if (page != null && count != null)
                          'Page $page of $count',
                      ].join(' · '),
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
              ],
            ),
          ),
          IconButton(
            tooltip: searching ? 'Close search' : 'Search in document',
            isSelected: searching,
            icon: const Icon(Icons.search),
            onPressed: canSearch ? onSearch : null,
          ),
          if (download case final download?)
            _HeaderDownload(
              key: ValueKey(source.cacheKey),
              download: download,
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

/// The header's Download, among its actions: the download's outcome shows in
/// its icon, as a file row's does.
///
/// Keyed by the open file: another file's download can read another signal,
/// and a `Watch` rebuilt with a builder that reads a different signal shows
/// its value once but stays subscribed to the signals it last tracked.
class _HeaderDownload extends StatelessWidget {
  const _HeaderDownload({super.key, required this.download});

  final PdfDownload download;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final state = download.state();
      final (icon, label) = state.affordance;
      return IconButton(
        // A spinner in the icon's place; the tooltip already names it to a
        // screen reader.
        icon: state is DownloadRunning
            ? ExcludeSemantics(child: ProgressRing(label: label))
            : Icon(icon, color: state.outcomeColor(colorScheme)),
        tooltip: label,
        onPressed: state.canStart ? () => download.start(context) : null,
      );
    });
  }
}

/// Above the document, under the header (and the search bar while it is
/// open), why the download failed, with a retry: the header's icon shows a
/// failure but says why only in its tooltip. Shown until the download starts
/// again, is cleared or is dismissed, and not where the page's own Download
/// already says why; announced to a screen reader. Keyed by the open file,
/// for the reason [_HeaderDownload] gives.
class _DownloadFailureNotice extends StatelessWidget {
  const _DownloadFailureNotice({
    super.key,
    required this.download,
    required this.dismissed,
    required this.onDismiss,
  });

  final PdfDownload download;
  final DownloadFailed? dismissed;
  final ValueChanged<DownloadFailed> onDismiss;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = download.state();
      if (state is! DownloadFailed || identical(state, dismissed)) {
        return const SizedBox.shrink();
      }
      final colorScheme = Theme.of(context).colorScheme;
      return Semantics(
        liveRegion: true,
        child: Align(
          alignment: Alignment.centerLeft,
          child: NoticePill(
            icon: Icons.error_outline,
            background: colorScheme.errorContainer,
            foreground: colorScheme.onErrorContainer,
            message: 'Download failed: ${state.reason}',
            actionLabel: 'Retry',
            onAction: () => download.start(context),
            onDismiss: () => onDismiss(state),
          ),
        ),
      );
    });
  }
}

/// A labelled Download in the viewer's body, loading while the download
/// runs, and under it why a failed one failed. Keyed by the open file where
/// another file can replace it in place, for the reason [_HeaderDownload]
/// gives.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({super.key, required this.download});

  final PdfDownload download;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Watch((context) {
      final state = download.state();
      final (icon, label) = state.buttonAffordance;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SoliplexButton.outlined(
            onPressed: state.canStart ? () => download.start(context) : null,
            isLoading: state is DownloadRunning,
            icon: Icon(icon),
            child: Text(label),
          ),
          // Always laid out, empty but for a failure, so the message around
          // it, centred, does not move when a reason comes and goes.
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            switch (state) {
              DownloadFailed(:final reason) => reason,
              DownloadIdle() || DownloadRunning() || DownloadSaved() => '',
            },
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      );
    });
  }
}
