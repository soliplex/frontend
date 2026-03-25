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
  });

  final ThreadListStatus threadListStatus;
  final String? selectedThreadId;
  final void Function(String threadId) onThreadSelected;
  final VoidCallback onBackToLobby;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildContent(context)),
        const Divider(height: 1),
        TextButton.icon(
          onPressed: onBackToLobby,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to Lobby'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (threadListStatus) {
      ThreadsLoading() => const Center(child: CircularProgressIndicator()),
      ThreadsFailed(:final error) => Center(
          child: Text('Failed to load threads: $error'),
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
