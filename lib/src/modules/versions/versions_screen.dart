import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show BackendVersionInfo;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../version.dart';
import '../../core/routes.dart';
import '../../design/design.dart';
import '../auth/server_entry.dart';
import '../auth/server_manager.dart';
import 'app_version_loader.dart';
import 'backend_version_fetcher.dart';

final _logger = LogManager.instance.getLogger('versions');

class VersionsScreen extends StatefulWidget {
  const VersionsScreen({
    super.key,
    required this.appName,
    required this.serverManager,
    required this.versionLoader,
    required this.versionFetcher,
  });

  final String appName;
  final ServerManager serverManager;
  final AppVersionLoader versionLoader;
  final BackendVersionFetcher versionFetcher;

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  late final Future<String> _flavorVersion;

  @override
  void initState() {
    super.initState();
    _flavorVersion = _loadAndLog();
  }

  Future<String> _loadAndLog() async {
    try {
      return await widget.versionLoader();
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to load flavor version',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.watch(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.adaptive.arrow_back),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: const Text('Versions'),
      ),
      body: ListView(
        children: [
          _SectionHeader(label: 'Frontend'),
          _AppRow(appName: widget.appName, versionFuture: _flavorVersion),
          const _FrameworkRow(),
          const Divider(height: 1),
          _SectionHeader(
            label: 'Servers (${servers.length})',
          ),
          if (servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(SoliplexSpacing.s4),
              child: Text(
                'No servers connected. Connect to a server to see its '
                'backend version.',
              ),
            )
          else
            for (final entry in servers.values)
              _ServerVersionTile(
                key: ValueKey(entry.serverId),
                entry: entry,
                versionFetcher: widget.versionFetcher,
              ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s2,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.appName, required this.versionFuture});

  final String appName;
  final Future<String> versionFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: versionFuture,
      builder: (context, snapshot) {
        final isDone = snapshot.connectionState == ConnectionState.done;
        final hasError = snapshot.hasError;
        final resolved = isDone && !hasError ? snapshot.data : null;
        final version = switch ((isDone, hasError, resolved)) {
          (true, true, _) => 'Unavailable',
          (true, false, final v?) => v,
          _ => 'Loading…',
        };
        return ListTile(
          leading: const Icon(Icons.smartphone_outlined),
          title: const Text('App'),
          subtitle: SelectableText('$appName $version'),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: resolved == null
                ? null
                : () => Clipboard.setData(
                      ClipboardData(text: '$appName $resolved'),
                    ),
          ),
        );
      },
    );
  }
}

class _FrameworkRow extends StatelessWidget {
  const _FrameworkRow();

  @override
  Widget build(BuildContext context) {
    final value = 'soliplex_frontend $soliplexVersion';
    return ListTile(
      leading: const Icon(Icons.widgets_outlined),
      title: const Text('Framework'),
      subtitle: SelectableText(value),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: 'Copy',
        onPressed: () => Clipboard.setData(ClipboardData(text: value)),
      ),
    );
  }
}

class _ServerVersionTile extends StatefulWidget {
  const _ServerVersionTile({
    super.key,
    required this.entry,
    required this.versionFetcher,
  });

  final ServerEntry entry;
  final BackendVersionFetcher versionFetcher;

  @override
  State<_ServerVersionTile> createState() => _ServerVersionTileState();
}

class _ServerVersionTileState extends State<_ServerVersionTile> {
  late Future<BackendVersionInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchAndLog();
  }

  Future<BackendVersionInfo> _fetchAndLog() async {
    try {
      return await widget.versionFetcher(widget.entry);
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to load backend version for ${widget.entry.serverId}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _future = _fetchAndLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BackendVersionInfo>(
      future: _future,
      builder: (context, snapshot) {
        final state = snapshot.connectionState;
        final isDone = state == ConnectionState.done;
        final hasError = snapshot.hasError;
        final info = isDone && !hasError ? snapshot.data : null;
        final url = formatServerUrl(widget.entry.serverUrl);

        return ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: SelectableText(url),
          subtitle: switch ((isDone, hasError, info)) {
            (false, _, _) => const Text('Loading…'),
            (true, true, _) => const Text('Unavailable'),
            (true, false, BackendVersionInfo(:final soliplexVersion)) =>
              SelectableText('Backend version: $soliplexVersion'),
            _ => const Text('Unavailable'),
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDone && hasError)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Retry',
                  onPressed: _retry,
                )
              else
                TextButton(
                  onPressed: info == null
                      ? null
                      : () => context.push(
                            AppRoutes.versionsForServer(widget.entry.alias),
                          ),
                  child: const Text('View packages'),
                ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy',
                onPressed: info == null
                    ? null
                    : () => Clipboard.setData(
                          ClipboardData(
                            text: '$url ${info.soliplexVersion}',
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}
