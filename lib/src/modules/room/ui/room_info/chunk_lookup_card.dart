import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show SoliplexApi;
import 'package:soliplex_design/soliplex_design.dart';

import '../chunk_visualization_page.dart';
import 'room_info_widgets.dart';

/// A free-form chunk-id lookup: enter a chunk id and open its
/// [ChunkVisualizationPage]. Complements the citation-tap entry point for
/// cases where the id is known up front (logs, support triage).
class ChunkLookupCard extends StatefulWidget {
  const ChunkLookupCard({
    super.key,
    required this.api,
    required this.roomId,
  });

  final SoliplexApi api;
  final String roomId;

  @override
  State<ChunkLookupCard> createState() => _ChunkLookupCardState();
}

class _ChunkLookupCardState extends State<ChunkLookupCard> {
  final _controller = TextEditingController();
  String _chunkId = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _view() {
    final id = _chunkId.trim();
    if (id.isEmpty) return;
    ChunkVisualizationPage.show(
      context: context,
      api: widget.api,
      roomId: widget.roomId,
      chunkId: id,
      // No document title or page numbers are known for a bare id lookup; the
      // title bar falls back to showing the chunk id.
      pageNumbers: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _chunkId.trim().isNotEmpty;
    return SectionCard(
      title: 'VIEW CHUNK',
      children: [
        SoliplexInput(
          controller: _controller,
          hintText: 'Enter chunk ID',
          leadingIcon: const Icon(Icons.search),
          textInputAction: TextInputAction.go,
          trailingIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () => setState(() {
                    _controller.clear();
                    _chunkId = '';
                  }),
                )
              : null,
          onChanged: (value) => setState(() => _chunkId = value),
          onSubmitted: (_) => _view(),
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        Align(
          alignment: Alignment.centerRight,
          child: SoliplexButton.filled(
            onPressed: hasText ? _view : null,
            child: const Text('View chunk'),
          ),
        ),
      ],
    );
  }
}
