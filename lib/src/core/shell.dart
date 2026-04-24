import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/theme_provider.dart';
import 'router.dart';
import 'shell_config.dart';

/// Boots the Soliplex shell from a [ShellConfig].
///
/// Validates routes before calling [runApp]. Throws [ArgumentError] if the
/// route configuration is invalid (e.g. duplicate paths).
///
/// Uses [UniqueKey] so that hot restart (which re-runs main) creates a fresh
/// widget tree. Hot reload does not re-run main, so this is safe.
void runSoliplexShell(ShellConfig config) {
  final errors = config.validate();
  if (errors.isNotEmpty) {
    throw ArgumentError('Invalid route configuration:\n${errors.join('\n')}');
  }

  runApp(SoliplexShell(key: UniqueKey(), config: config));
}

class SoliplexShell extends StatefulWidget {
  final ShellConfig config;

  const SoliplexShell({super.key, required this.config});

  @override
  State<SoliplexShell> createState() => _SoliplexShellState();
}

class _SoliplexShellState extends State<SoliplexShell> {
  late final _router = buildRouter(widget.config);

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: widget.config.overrides,
      child: _ThemedApp(config: widget.config, router: _router),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    widget.config.onDispose?.call();
    super.dispose();
  }
}

class _ThemedApp extends ConsumerWidget {
  const _ThemedApp({required this.config, required this.router});

  final ShellConfig config;
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: config.appName,
      theme: config.theme,
      darkTheme: config.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
