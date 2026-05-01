import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_client/soliplex_client.dart' show BackendVersionInfo;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/routes.dart';
import '../../design/design.dart';
import '../auth/server_entry.dart';
import 'backend_version_fetcher.dart';

final _logger = LogManager.instance.getLogger('versions');

class ServerVersionsScreen extends StatefulWidget {
  const ServerVersionsScreen({
    super.key,
    required this.serverEntry,
    required this.versionFetcher,
  });

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
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.adaptive.arrow_back),
          tooltip: 'Back to versions',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.versions),
        ),
        title: Text(url),
      ),
      body: FutureBuilder<BackendVersionInfo>(
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
          return _buildContent(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildContent(BackendVersionInfo info) {
    final filtered = _filterPackages(info.packageVersions);
    final sortedKeys = filtered.keys.toList()..sort();
    final total = info.packageVersions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search packages…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
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
