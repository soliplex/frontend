import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/routes.dart';
import '../auth/server_entry.dart';
import '../auth/ui/home_shell.dart';
import 'bandwidth_preference.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.appName,
    required this.preference,
    required this.servers,
    this.logo,
  });

  final String appName;
  final Widget? logo;
  final BandwidthPreference preference;

  /// The servers whose support for low bandwidth mode the page lists.
  final ReadonlySignal<Map<String, ServerEntry>> servers;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  /// Whether the last change failed to save. A later save that succeeds
  /// clears it, so the banner never speaks for a value already stored.
  bool _unsaved = false;

  @override
  void initState() {
    super.initState();
    // Opening the page refreshes what each server offers, which also replaces
    // a profile name the server has since changed.
    if (widget.preference.lowBandwidth.value) _checkServers();
  }

  void _checkServers() => unawaited(
        widget.preference.checkServers([
          for (final entry in widget.servers.value.values) entry.connection,
        ]),
      );

  Future<void> _setLowBandwidth(bool value) async {
    if (value) _checkServers();
    final saved = await widget.preference.setLowBandwidth(value);
    if (!mounted) return;
    setState(() => _unsaved = !saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            HomeShellHeader(
              appName: widget.appName,
              logo: widget.logo,
              showUtilityMenu: false,
              leading: IconButton(
                icon: Icon(Icons.adaptive.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.home),
              ),
            ),
            if (_unsaved)
              _UnsavedBanner(
                onDismiss: () => setState(() => _unsaved = false),
              ),
            Expanded(
              child: ListView(
                children: [
                  Watch(
                    (context) => SwitchListTile(
                      title: const Text('Low bandwidth mode'),
                      subtitle: const Text(
                        "Show each reply once it's complete instead of "
                        "streaming it as it's written. Uses less data on "
                        'slow connections, on servers that support it.',
                      ),
                      value: widget.preference.lowBandwidth.value,
                      onChanged: _setLowBandwidth,
                    ),
                  ),
                  _ServerSupport(
                    preference: widget.preference,
                    servers: widget.servers,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// While low bandwidth mode is on, names the servers that cannot honour it,
/// apart from those whose support could not be checked.
class _ServerSupport extends StatelessWidget {
  const _ServerSupport({required this.preference, required this.servers});

  final BandwidthPreference preference;
  final ReadonlySignal<Map<String, ServerEntry>> servers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Watch((context) {
      if (!preference.lowBandwidth.value) return const SizedBox.shrink();
      final lookups = preference.profileLookups.value;
      final entries = servers.value.values;
      List<String> namesWhere(bool Function(ProfileLookup?) test) => [
            for (final entry in entries)
              if (test(lookups[entry.serverId])) entry.displayName,
          ];
      final checking = namesWhere((l) => l is ProfileChecking).isNotEmpty;
      final notOffered = namesWhere((l) => l is ProfileNotOffered);
      final unchecked = namesWhere((l) => l is ProfileCouldNotCheck);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          SoliplexSpacing.s4,
          0,
          SoliplexSpacing.s4,
          SoliplexSpacing.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (checking)
              Row(
                children: [
                  const SizedBox.square(
                    dimension: SoliplexSpacing.s3,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Text('Checking servers…', style: style),
                ],
              ),
            if (notOffered.isNotEmpty)
              Text('Not available on: ${notOffered.join(', ')}', style: style),
            if (unchecked.isNotEmpty)
              Text("Couldn't check: ${unchecked.join(', ')}", style: style),
          ],
        ),
      );
    });
  }
}

/// Tells the user the last change applies to this session only.
class _UnsavedBanner extends StatelessWidget {
  const _UnsavedBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.of(context).colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      color: colors.warningContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: colors.onWarningContainer,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              "Couldn't save this preference. It applies until the app "
              'restarts.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onWarningContainer),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
