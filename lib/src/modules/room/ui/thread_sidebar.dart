import 'package:flutter/material.dart';

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
    required this.onRoomInfo,
    this.onRetryThreads,
  });

  final ThreadListStatus threadListStatus;
  final String? selectedThreadId;
  final void Function(String threadId) onThreadSelected;
  final VoidCallback onBackToLobby;
  final VoidCallback onCreateThread;
  final VoidCallback onNetworkInspector;
  final VoidCallback onRoomInfo;
  final VoidCallback? onRetryThreads;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onBackToLobby,
              icon: const Icon(Icons.arrow_back, size: 24),
              label: const Text('Lobby'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s5),
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
        const Divider(height: 4),
        Expanded(child: _buildContent(context)),
        const Divider(height: 4),
        TextButton.icon(
          onPressed: onRoomInfo,
          icon: const Icon(Icons.info_outline, size: 16),
          label: const Text('Room Info'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const Divider(height: 4),
        TextButton.icon(
          onPressed: onNetworkInspector,
          icon: const Icon(Icons.lan, size: 16),
          label: const Text('Network Inspector'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
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
