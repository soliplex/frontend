import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_client/soliplex_client.dart' show BackendVersionInfo;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/routes.dart';
import 'package:soliplex_design/soliplex_design.dart';
import '../auth/server_entry.dart';
import '../auth/ui/home_shell.dart';
import 'backend_version_fetcher.dart';

final _logger = LogManager.instance.getLogger('versions');

class ServerVersionsScreen extends StatefulWidget {
  const ServerVersionsScreen({
    super.key,
    required this.appName,
    required this.serverEntry,
    required this.versionFetcher,
    this.logo,
  });

  final String appName;
  final Widget? logo;
  final ServerEntry serverEntry;
  final BackendVersionFetcher versionFetcher;

  @override
  State<ServerVersionsScreen> createState() => _ServerVersionsScreenState();
}

class _ServerVersionsScreenState extends State<ServerVersionsScreen> {
  late final Future<BackendVersionInfo> _future;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _fetchAndLog();
  }

  Future<BackendVersionInfo> _fetchAndLog() async {
    try {
      return await widget.versionFetcher(widget.serverEntry);
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to load packages for ${widget.serverEntry.serverId}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = formatServerUrl(widget.serverEntry.serverUrl);
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
                tooltip: 'Back to versions',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.versions),
              ),
            ),
            Expanded(
              child: FutureBuilder<BackendVersionInfo>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Failed to load version information'),
                    );
                  }
                  return _buildContent(url, snapshot.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String url, BackendVersionInfo info) {
    final filtered = _filterPackages(info.packageVersions);
    final sortedKeys = filtered.keys.toList()..sort();
    final total = info.packageVersions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4,
            SoliplexSpacing.s4,
            SoliplexSpacing.s4,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  widget.serverEntry.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                // Show the raw address beneath the name only when a friendly
                // name is present, so it stays available without duplicating
                // the title for unnamed servers.
                if (widget.serverEntry.name != null) ...[
                  const SizedBox(height: SoliplexSpacing.s1),
                  SelectableText(
                    url,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: SoliplexInput(
            controller: _searchController,
            hintText: 'Search packages…',
            leadingIcon: const Icon(Icons.search),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s4,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _searchQuery.isEmpty
                  ? '$total packages'
                  : '${sortedKeys.length} of $total packages',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        Expanded(
          child: sortedKeys.isEmpty
              ? Center(
                  child: Text(
                    total == 0
                        ? 'No packages reported'
                        : 'No packages match your search',
                  ),
                )
              : ListView.builder(
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, index) {
                    final name = sortedKeys[index];
                    final version = filtered[name]!;
                    return ListTile(
                      title: SelectableText(name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(version),
                          const SizedBox(width: SoliplexSpacing.s2),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy',
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: '$name $version'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Map<String, String> _filterPackages(Map<String, String> packages) {
    if (_searchQuery.isEmpty) return packages;
    final query = _searchQuery.toLowerCase();
    return Map.fromEntries(
      packages.entries.where((e) => e.key.toLowerCase().contains(query)),
    );
  }
}
