import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../thread_list_state.dart';
import 'error_retry_panel.dart';
import 'thread_tile.dart';
import 'package:soliplex_design/soliplex_design.dart';

class ThreadSidebar extends StatelessWidget {
  const ThreadSidebar({
    super.key,
    required this.threadListStatus,
    required this.selectedThreadId,
    required this.onThreadSelected,
    required this.onBackToLobby,
    required this.onCreateThread,
    required this.onNetworkInspector,
    required this.onVersions,
    required this.onRoomInfo,
    required this.roomName,
    required this.runningThreadIds,
    this.onRetryThreads,
    this.onReauthenticate,
    this.quizzes = const {},
    this.onQuizTapped,
    this.onRenameThread,
    this.onDeleteThread,
  });

  final ThreadListStatus threadListStatus;
  final String? selectedThreadId;
  final void Function(String threadId) onThreadSelected;
  final VoidCallback onBackToLobby;
  final VoidCallback onCreateThread;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;
  final VoidCallback onRoomInfo;
  final String roomName;
  final Future<void> Function()? onRetryThreads;
  final VoidCallback? onReauthenticate;
  final Map<String, String> quizzes;
  final void Function(String quizId)? onQuizTapped;
  final void Function(String threadId, String currentName)? onRenameThread;
  final void Function(String threadId)? onDeleteThread;
  final ReadonlySignal<Set<String>> runningThreadIds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s1, vertical: SoliplexSpacing.s1),
          child: Row(
            children: [
              SoliplexButton.text(
                onPressed: onBackToLobby,
                isCompact: true,
                icon: const Icon(Icons.arrow_back, size: 16),
                child: const Text('Lobby'),
              ),
              const Spacer(),
              SoliplexButton.text(
                onPressed: onCreateThread,
                isCompact: true,
                icon: const Icon(Icons.add, size: 16),
                child: const Text('New Thread'),
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
        SoliplexButton.text(
          onPressed: onRoomInfo,
          isCompact: true,
          icon: const Icon(Icons.info_outline, size: 16),
          child: Text(roomName),
        ),
        SoliplexButton.text(
          onPressed: onNetworkInspector,
          isCompact: true,
          icon: const Icon(Icons.http, size: 16),
          child: const Text('Network Inspector'),
        ),
        SoliplexButton.text(
          onPressed: onVersions,
          isCompact: true,
          icon: const Icon(Icons.info_outline, size: 16),
          child: const Text('Versions'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (threadListStatus) {
      ThreadsLoading() => const Center(child: CircularProgressIndicator()),
      ThreadsFailed(:final error) => Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: ErrorRetryPanel(
            title: 'Failed to load threads',
            error: error,
            onRetry: onRetryThreads,
            onReauthenticate: onReauthenticate,
          ),
        ),
      ThreadsLoaded(:final threads) => _wrapWithRefresh(
          threads.isEmpty
              ? ListView(
                  children: const [
                    Center(
                        child: Padding(
                      padding: EdgeInsets.only(top: SoliplexSpacing.s6),
                      child: Text('No threads'),
                    )),
                  ],
                )
              : Watch((context) {
                  final running = runningThreadIds.value;
                  return ListView.builder(
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return ThreadTile(
                        thread: thread,
                        isSelected: thread.id == selectedThreadId,
                        isRunning: running.contains(thread.id),
                        onTap: () => onThreadSelected(thread.id),
                        onRename: () =>
                            onRenameThread?.call(thread.id, thread.name),
                        onDelete: () => onDeleteThread?.call(thread.id),
                      );
                    },
                  );
                }),
        ),
    };
  }

  Widget _wrapWithRefresh(Widget child) {
    final handler = onRetryThreads;
    if (handler == null) return child;
    return RefreshIndicator(
      onRefresh: handler,
      child: child,
    );
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
        onPressed: widget.onQuizTapped != null
            ? () => widget.onQuizTapped!(entry.key)
            : null,
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
              onPressed: widget.onQuizTapped != null
                  ? () => widget.onQuizTapped!(entry.key)
                  : null,
              indent: true,
            ),
      ],
    );
  }

  Widget _quizButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool indent = false,
  }) {
    final button = SoliplexButton.text(
      onPressed: onPressed,
      isCompact: true,
      alignment: Alignment.centerLeft,
      icon: Icon(icon, size: 16),
      child: Text(label),
    );
    // Nested quiz rows indent under the "Quizzes (N)" expander. The
    // compact button already carries s2 of leading padding, so an extra
    // s4 lands the content at the same offset as the old hand-rolled 24.
    if (!indent) return button;
    return Padding(
      padding: const EdgeInsets.only(left: SoliplexSpacing.s4),
      child: button,
    );
  }
}
