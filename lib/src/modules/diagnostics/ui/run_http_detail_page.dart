import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../models/http_event_group.dart';
import 'http_exchange_tile.dart';

/// Shows the HTTP traffic captured for a single agent run as a list of
/// expandable exchange tiles. A single exchange opens expanded.
class RunHttpDetailPage extends StatelessWidget {
  const RunHttpDetailPage({
    required this.groups,
    super.key,
  });

  final List<HttpEventGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('HTTP Traffic')),
        body: _buildEmptyState(context),
      );
    }

    final single = groups.length == 1;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(single ? 'HTTP Traffic' : 'HTTP Traffic (${groups.length})'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tabular = constraints.maxWidth >= SoliplexBreakpoints.tablet;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => HttpExchangeTile(
              key: ValueKey(groups[index].requestId),
              group: groups[index],
              tabular: tabular,
              initiallyExpanded: single,
            ),
          );
        },
      ),
    );
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
          const SizedBox(height: SoliplexSpacing.s3),
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
