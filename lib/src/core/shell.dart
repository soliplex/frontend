import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'inactivity/inactivity_dialog_host.dart';
import 'inactivity/inactivity_monitor.dart';
import 'inactivity/inactivity_provider.dart';
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
      overrides: [
        ...widget.config.overrides,
        inactivityConfigProvider.overrideWithValue(widget.config.inactivity),
      ],
      child: _ShellRoot(config: widget.config, router: _router),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}

/// Lives inside [ProviderScope] so it can read the [InactivityMonitor]
/// via Riverpod. Owns the global activity listeners (pointer + keyboard)
/// and wraps [MaterialApp.router]'s builder slot with the dialog host.
class _ShellRoot extends ConsumerStatefulWidget {
  const _ShellRoot({required this.config, required this.router});

  final ShellConfig config;
  final GoRouter router;

  @override
  ConsumerState<_ShellRoot> createState() => _ShellRootState();
}

class _ShellRootState extends ConsumerState<_ShellRoot> {
  late final InactivityMonitor _monitor = ref.read(inactivityMonitorProvider);

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard sees every key the framework receives, regardless
    // of which widget owns focus — a root `Focus` widget would miss keys
    // consumed by descendants like `TextField`.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _monitor.bumpActivity();
    // Returning false lets the framework continue normal dispatch.
    return false;
  }

  void _onPointer(PointerEvent _) => _monitor.bumpActivity();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      // `onPointerSignal` fires on trackpad/wheel scroll on desktop and
      // web. On mobile, scrolling is a drag gesture starting with
      // `onPointerDown`.
      onPointerSignal: _onPointer,
      child: MaterialApp.router(
        title: widget.config.appName,
        theme: widget.config.lightTheme,
        darkTheme: widget.config.darkTheme,
        themeMode: widget.config.themeMode,
        routerConfig: widget.router,
        builder: (context, child) {
          return InactivityDialogHost(
            monitor: _monitor,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
