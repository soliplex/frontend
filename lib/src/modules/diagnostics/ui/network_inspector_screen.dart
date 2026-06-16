import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../../../core/routes.dart';
import '../../auth/ui/home_shell.dart';
import '../models/http_event_group.dart';
import '../models/http_event_grouper.dart';
import '../network_inspector.dart';
import 'concurrency_summary_panel.dart';
import 'http_event_tile.dart';
import 'request_detail_view.dart';

class NetworkInspectorScreen extends StatefulWidget {
  const NetworkInspectorScreen({
    required this.appName,
    required this.inspector,
    this.logo,
    super.key,
  });

  final String appName;
  final Widget? logo;
  final NetworkInspector inspector;

  @override
  State<NetworkInspectorScreen> createState() => _NetworkInspectorScreenState();
}

class _NetworkInspectorScreenState extends State<NetworkInspectorScreen> {
  String? _selectedRequestId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inspector,
      builder: (context, _) {
        final groups = groupHttpEvents(widget.inspector.events);
        final sortedGroups = groups.reversed.toList();

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                HomeShellHeader(
                  appName: widget.appName,
                  logo: widget.logo,
                  showAbout: false,
                  leading: IconButton(
                    icon: Icon(Icons.adaptive.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.lobby),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: widget.inspector.events.isEmpty &&
                              widget.inspector.concurrencyEvents.isEmpty
                          ? null
                          : () {
                              widget.inspector.clear();
                              setState(() => _selectedRequestId = null);
                            },
                      tooltip: 'Clear all requests',
                    ),
                  ],
                ),
                ConcurrencySummaryPanel(
                  events: widget.inspector.concurrencyEvents,
                ),
                if (sortedGroups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SoliplexSpacing.s4,
                      SoliplexSpacing.s4,
                      SoliplexSpacing.s4,
                      SoliplexSpacing.s2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Requests (${sortedGroups.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (sortedGroups.isEmpty) {
                        return _buildEmptyState(context);
                      }
                      final isWide =
                          constraints.maxWidth >= SoliplexBreakpoints.tablet;
                      if (isWide) {
                        return _buildMasterDetailLayout(context, sortedGroups);
                      }
                      return _buildListLayout(context, sortedGroups);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          Text(
            'No HTTP requests yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            'Requests will appear here as you use the app',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListLayout(BuildContext context, List<HttpEventGroup> groups) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = groups[index];
        return HttpEventTile(
          group: group,
          onTap: () => _navigateToDetail(context, group),
        );
      },
    );
  }

  Widget _buildMasterDetailLayout(
    BuildContext context,
    List<HttpEventGroup> groups,
  ) {
    final theme = Theme.of(context);
    final selectedGroup = _selectedRequestId != null
        ? groups.where((g) => g.requestId == _selectedRequestId).firstOrNull
        : null;
    final effectiveGroup = selectedGroup ?? groups.firstOrNull;
    final effectiveId = effectiveGroup?.requestId;

    return Row(
      children: [
        SizedBox(
          width: 360,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = groups[index];
                final isSelected = group.requestId == effectiveId;
                return InkWell(
                  onTap: () =>
                      setState(() => _selectedRequestId = group.requestId),
                  child: Container(
                    color:
                        isSelected ? theme.colorScheme.primaryContainer : null,
                    child: HttpEventTile(group: group, isSelected: isSelected),
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: effectiveGroup != null
              ? RequestDetailView(group: effectiveGroup)
              : Center(
                  child: Text(
                    'Select a request to view details',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _navigateToDetail(BuildContext context, HttpEventGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(group.pathWithQuery)),
          body: RequestDetailView(group: group),
        ),
      ),
    );
  }
}
