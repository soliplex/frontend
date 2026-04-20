import 'package:flutter/material.dart';

import '../models/http_event_group.dart';
import 'http_event_tile.dart';
import 'request_detail_view.dart';

class RunHttpDetailPage extends StatelessWidget {
  const RunHttpDetailPage({required this.groups, super.key});

  final List<HttpEventGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('HTTP Traffic')),
        body: _buildEmptyState(context),
      );
    }

    if (groups.length == 1) {
      return Scaffold(
        appBar: AppBar(title: Text(groups[0].pathWithQuery)),
        body: RequestDetailView(group: groups[0]),
      );
    }

    return _MultiGroupView(groups: groups);
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.http,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No HTTP traffic found for this run',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiGroupView extends StatelessWidget {
  const _MultiGroupView({required this.groups});

  final List<HttpEventGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('HTTP Traffic (${groups.length})')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final group = groups[index];
          return HttpEventTile(
            group: group,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (context) => Scaffold(
                          appBar: AppBar(title: Text(group.pathWithQuery)),
                          body: RequestDetailView(group: group),
                        ),
                  ),
                ),
          );
        },
      ),
    );
  }
}
