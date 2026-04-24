import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;

import '../../../../soliplex_frontend.dart';

@visibleForTesting
class PageImage {
  const PageImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;

  bool get hasDimensions => width > 0 && height > 0;
}

/// Reads dimensions from a PNG IHDR chunk (bytes 16–23).
/// Returns (0, 0) for non-PNG, missing IHDR, or truncated data.
@visibleForTesting
(int, int) readPngDimensions(Uint8List bytes) {
  // Full 8-byte PNG signature + 4-byte chunk length + 4-byte "IHDR" + 8 bytes
  // for width and height = 24 bytes minimum.
  if (bytes.length < 24) return (0, 0);

  // PNG signature: 137 80 78 71 13 10 26 10
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < sig.length; i++) {
    if (bytes[i] != sig[i]) return (0, 0);
  }

  // First chunk must be IHDR (bytes 12–15: 0x49 0x48 0x44 0x52).
  if (bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return (0, 0);
  }

  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
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
  });

  final SoliplexApi api;
  final String roomId;
  final String chunkId;
  final String documentTitle;
  final List<int> pageNumbers;
  final bool useDialogLayout;

  static Future<void> show({
    required BuildContext context,
    required SoliplexApi api,
    required String roomId,
    required String chunkId,
    required String documentTitle,
    required List<int> pageNumbers,
  }) {
    final useDialog = MediaQuery.sizeOf(context).width >= 600;
    final child = ChunkVisualizationPage(
      api: api,
      roomId: roomId,
      chunkId: chunkId,
      documentTitle: documentTitle,
      pageNumbers: pageNumbers,
      useDialogLayout: useDialog,
    );

    if (useDialog) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => child,
      );
    }

    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => child),
    );
  }

  @override
  State<ChunkVisualizationPage> createState() => _ChunkVisualizationPageState();
}

class _ChunkVisualizationPageState extends State<ChunkVisualizationPage> {
  late Future<List<PageImage>> _future;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final Map<int, int> _rotations = {};

  @override
  void initState() {
    super.initState();
    _loadVisualization();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadVisualization() {
    _future = widget.api
        .getChunkVisualization(widget.roomId, widget.chunkId)
        .then((viz) => viz.imagesBase64.map((b64) {
              final bytes = base64Decode(b64);
              final (w, h) = readPngDimensions(bytes);
              return PageImage(bytes, w, h);
            }).toList());
  }

  void _retry() {
    setState(() {
      _rotations.clear();
      _loadVisualization();
    });
  }

  void _rotate(int pageIndex) {
    setState(() {
      _rotations[pageIndex] = ((_rotations[pageIndex] ?? 0) + 1) % 4;
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
        titleTextStyle: SoliplexTheme.appBarTitleStyle(context),
      ),
      body: _buildContent(context),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPageImage(PageImage page, int rotation) {
    final image = RotatedBox(
      quarterTurns: rotation,
      child: Image.memory(page.bytes, fit: BoxFit.contain),
    );

    if (!page.hasDimensions) {
      return Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: image,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final effW = rotation.isOdd ? page.height : page.width;
        final effH = rotation.isOdd ? page.width : page.height;
        final scale = min(
          constraints.maxWidth / effW,
          constraints.maxHeight / effH,
        );
        return Center(
          child: InteractiveViewer(
            constrained: false,
            minScale: 1.0,
            maxScale: 4.0,
            child: SizedBox(
              width: effW * scale,
              height: effH * scale,
              child: image,
            ),
          ),
        );
      },
    );
  }

  Widget _buildImages(BuildContext context, List<PageImage> pages) {
    if (pages.isEmpty) {
      return const Center(child: Text('No page images available'));
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final page = pages[index];
              final rotation = _rotations[index] ?? 0;
              return Stack(
                children: [
                  _buildPageImage(page, rotation),
                  Positioned(
                    right: SoliplexSpacing.s2,
                    top: SoliplexSpacing.s2,
                    child: IconButton.filledTonal(
                      onPressed: () => _rotate(index),
                      icon: const Icon(Icons.rotate_right),
                      tooltip: 'Rotate',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          child: Column(
            children: [
              Text(
                _pageLabel(_currentPage, pages.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (pages.length > 1) ...[
                const SizedBox(height: SoliplexSpacing.s1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pages.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SoliplexSpacing.s1),
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: index == _currentPage
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.3),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
