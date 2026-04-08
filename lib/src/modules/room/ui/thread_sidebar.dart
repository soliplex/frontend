import 'package:flutter/material.dart';

import '../thread_list_state.dart';
import 'error_retry_panel.dart';
import 'thread_tile.dart';

class ThreadSidebar extends StatelessWidget {
  const ThreadSidebar({
    super.key,
    required this.threadListStatus,
    required this.selectedThreadId,
    required this.onThreadSelected,
    required this.onBackToLobby,
    required this.onCreateThread,
    required this.onNetworkInspector,
    required this.onRoomInfo,
    this.onRetryThreads,
    this.quizzes = const {},
    this.onQuizTapped,
  });

  final ThreadListStatus threadListStatus;
  final String? selectedThreadId;
  final void Function(String threadId) onThreadSelected;
  final VoidCallback onBackToLobby;
  final VoidCallback onCreateThread;
  final VoidCallback onNetworkInspector;
  final VoidCallback onRoomInfo;
  final VoidCallback? onRetryThreads;
  final Map<String, String> quizzes;
  final void Function(String quizId)? onQuizTapped;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: onBackToLobby,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Lobby'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCreateThread,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Thread'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (quizzes.isNotEmpty) ...[
          _QuizRow(
            quizzes: quizzes,
            onQuizTapped: onQuizTapped,
          ),
          const Divider(height: 1),
        ],
        Expanded(child: _buildContent(context)),
        const Divider(height: 1),
        TextButton.icon(
          onPressed: onRoomInfo,
          icon: const Icon(Icons.info_outline, size: 16),
          label: const Text('Room Info'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
        TextButton.icon(
          onPressed: onNetworkInspector,
          icon: const Icon(Icons.http, size: 16),
          label: const Text('Network Inspector'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (threadListStatus) {
      ThreadsLoading() => const Center(child: CircularProgressIndicator()),
      ThreadsFailed(:final error) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorRetryPanel(
            title: 'Failed to load threads',
            error: error,
            onRetry: onRetryThreads,
          ),
        ),
      ThreadsLoaded(:final threads) => threads.isEmpty
          ? const Center(child: Text('No threads'))
          : ListView.builder(
              itemCount: threads.length,
              itemBuilder: (context, index) {
                final thread = threads[index];
                return ThreadTile(
                  thread: thread,
                  isSelected: thread.id == selectedThreadId,
                  onTap: () => onThreadSelected(thread.id),
                );
              },
            ),
    };
  }
}

class _QuizRow extends StatefulWidget {
  const _QuizRow({required this.quizzes, this.onQuizTapped});
  final Map<String, String> quizzes;
  final void Function(String quizId)? onQuizTapped;

  @override
  State<_QuizRow> createState() => _QuizRowState();
}

class _QuizRowState extends State<_QuizRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.quizzes.length == 1) {
      final entry = widget.quizzes.entries.first;
      return _quizButton(
        icon: Icons.quiz,
        label: entry.value,
        onPressed: () => widget.onQuizTapped?.call(entry.key),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _quizButton(
          icon: _expanded ? Icons.expand_less : Icons.expand_more,
          label: 'Quizzes (${widget.quizzes.length})',
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final entry in widget.quizzes.entries)
            _quizButton(
              icon: Icons.play_arrow,
              label: entry.value,
              onPressed: () => widget.onQuizTapped?.call(entry.key),
              indent: true,
            ),
      ],
    );
  }

  Widget _quizButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool indent = false,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: indent ? 24 : 8,
        ),
        visualDensity: VisualDensity.compact,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}
