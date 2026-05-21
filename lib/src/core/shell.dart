import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  _clearFilePickerTempCacheOnMobile();
  runApp(SoliplexShell(key: UniqueKey(), config: config));
}

/// On mobile (Android / iOS), `file_picker` copies each picked file to
/// the app's cache directory at pick time to provide a POSIX path that
/// `dart:io` can read. Those copies accumulate across runs — the OS
/// purges them under storage pressure, but it's hygienic to clear last
/// session's leftovers at boot before any new picks happen.
///
/// `clearTemporaryFiles()` is implemented only on Android and iOS;
/// calling it on web, macOS, Windows, or Linux throws
/// `UnimplementedError`. The `kIsWeb` short-circuit is necessary
/// because `Platform.isAndroid` itself throws on web.
///
/// Fire-and-forget: errors during cleanup never block app startup.
void _clearFilePickerTempCacheOnMobile() {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  unawaited(
    FilePicker.clearTemporaryFiles().catchError((Object _) => false),
  );
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
      child: MaterialApp.router(
        title: widget.config.appName,
        theme: widget.config.lightTheme,
        darkTheme: widget.config.darkTheme,
        themeMode: widget.config.themeMode,
        routerConfig: _router,
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}
