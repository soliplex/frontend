import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/routes.dart';
import '../auth/ui/home_shell.dart';
import 'bandwidth_preference.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.appName,
    required this.preference,
    this.logo,
  });

  final String appName;
  final Widget? logo;
  final BandwidthPreference preference;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  /// Whether the last change failed to save. A later save that succeeds
  /// clears it, so the banner never speaks for a value already stored.
  bool _unsaved = false;

  Future<void> _setLowBandwidth(bool value) async {
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
                        'slow connections.',
                      ),
                      value: widget.preference.lowBandwidth.value,
                      onChanged: _setLowBandwidth,
                    ),
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
