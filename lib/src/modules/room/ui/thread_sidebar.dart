import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../../soliplex_frontend.dart';
import '../../../shared/theme_toggle_button.dart';
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
    required this.onVersions,
    required this.onRoomInfo,
    required this.roomName,
    required this.runningThreadIds,
    this.onRetryThreads,
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
  final Map<String, String> quizzes;
  final void Function(String quizId)? onQuizTapped;
  final void Function(String threadId, String currentName)? onRenameThread;
  final void Function(String threadId)? onDeleteThread;
  final ReadonlySignal<Set<String>> runningThreadIds;

  @override
  Widget build(BuildContext context) {
    final bool isMobile =
        MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
    final double verticalPadding =
        isMobile ? SoliplexSpacing.s5 : SoliplexSpacing.s8;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: onBackToLobby,
                icon: const Icon(Icons.arrow_back, size: 24),
                label: const Text('Lobby'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  padding: EdgeInsets.fromLTRB(
                    SoliplexSpacing.s2,
                    verticalPadding,
                    SoliplexSpacing.s4,
                    verticalPadding,
                  ),
                  textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                        height: isMobile ? 1.7 : 1.4,
                      ),
                ),
              ),
              const Spacer(),
              const ThemeToggleButton(),
              IconButton(
                onPressed: onCreateThread,
                icon: const Icon(Icons.add, size: 24),
                tooltip: 'New Thread',
              ),
            ],
          ),
          const Divider(),
          if (quizzes.isNotEmpty) ...[
            _QuizRow(
              quizzes: quizzes,
              onQuizTapped: onQuizTapped,
            ),
            const Divider(),
          ],
          Expanded(child: _buildContent(context)),
          const Divider(),
          TextButton.icon(
            onPressed: onRoomInfo,
            icon: const Icon(Icons.info_outline, size: 16),
            label: Text(roomName),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
          const Divider(),
          TextButton.icon(
            onPressed: onNetworkInspector,
            icon: const Icon(Icons.lan, size: 16),
            label: const Text('Network Inspector'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
          const Divider(),
          TextButton.icon(
            onPressed: onVersions,
            icon: const Icon(Icons.info_outline, size: 16),
            label: const Text('Versions'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
        ],
      ),
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
          ),
        ),
      ThreadsLoaded(:final threads) => _wrapWithRefresh(
          threads.isEmpty
              ? ListView(
                  children: const [
                    Center(
                        child: Padding(
                      padding: EdgeInsets.only(top: SoliplexSpacing.s8),
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
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
      ),
    );
  }
}
