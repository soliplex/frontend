import 'package:flutter/material.dart';

import '../thread_list_state.dart';
import 'thread_tile.dart';

class ThreadSidebar extends StatelessWidget {
  const ThreadSidebar({
    super.key,
    required this.threadListStatus,
    required this.selectedThreadId,
    required this.onThreadSelected,
    required this.onBackToLobby,
    required this.onCreateThread,
    this.onRetryThreads,
  });

  final ThreadListStatus threadListStatus;
  final String? selectedThreadId;
  final void Function(String threadId) onThreadSelected;
  final VoidCallback onBackToLobby;
  final VoidCallback onCreateThread;
  final VoidCallback? onRetryThreads;

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
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (threadListStatus) {
      ThreadsLoading() => const Center(child: CircularProgressIndicator()),
      ThreadsFailed(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to load threads',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: onRetryThreads,
                  child: const Text('Retry'),
                ),
              ],
            ),
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
