import 'dart:async' show FutureOr, unawaited;
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart' show SoliplexSpacing;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'inactivity/inactivity_dialog_host.dart';
import 'inactivity/inactivity_monitor.dart';
import 'inactivity/inactivity_provider.dart';
import 'router.dart';
import 'shell_config.dart';
import 'status_message_config.dart';

/// Boots the Soliplex shell, building its [ShellConfig] inside the guard.
///
/// Takes a builder rather than a built config because that is the only way to
/// catch what [Flavor.build] throws — an invalid route configuration, a theme
/// missing its extension, a duplicated namespace. Those land before the first
/// frame, and no target treats that as a crash — the launch surface simply
/// stays up (a splash on iOS, the window background on Android once
/// `FlutterActivity` has swapped `LaunchTheme` for `NormalTheme`, a black
/// window on macOS, the loader on web), and on Windows and Linux the runner
/// shows its window only once a frame arrives, so nothing appears at all. None
/// of them blocks the main thread, so no watchdog fires: the user gets a launch
/// that never finishes and nothing to send back, while the message naming the
/// fault goes nowhere. It is put on the device instead.
///
/// The error is rethrown once the failure surface is *scheduled*: `runApp`
/// both attaches the root widget and pumps the warm-up frame through
/// `Timer.run`, so the rethrow runs first and the frame follows. Both the
/// engine's report and [installUncaughtErrorLogging]'s asynchronous intake
/// still see it, unless the caller awaits this future and swallows it.
///
/// Uses [UniqueKey] so that hot restart (which re-runs main) creates a fresh
/// widget tree. Hot reload does not re-run main, so this is safe.
Future<void> runSoliplexShell(
  FutureOr<ShellConfig> Function() buildConfig,
) async {
  _clearFilePickerTempCacheOnMobile();
  try {
    runApp(SoliplexShell(key: UniqueKey(), config: await buildConfig()));
  } catch (error) {
    runApp(_BootFailureApp(error));
    rethrow;
  }
}

/// Shown when the app could not be assembled, so it uses no flavor, no theme
/// and no shell — any of which may be what failed.
class _BootFailureApp extends StatelessWidget {
  const _BootFailureApp(this.error);

  final Object error;

  /// A diagnosis this package composed is shown whole; anything else is
  /// reduced to its type.
  static String _describe(Object error) =>
      error is ShellDiagnosis ? error.diagnosis : describeFailure(error);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SoliplexSpacing.s6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This build could not start',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: SoliplexSpacing.s3),
                  Flexible(
                    child: SingleChildScrollView(
                      // Selectable so it can be copied off the device: on a
                      // packaged build this text exists nowhere else. Which is
                      // also why only a diagnosis this package composed is
                      // shown whole — anything else is reduced to its type,
                      // because an exception escaping the flavor's assembly can
                      // carry the value it failed on, and this screen needs no
                      // navigation and no export to read.
                      child: SelectableText(
                        _describe(error),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
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
/// Fire-and-forget: a failed cleanup never blocks app startup, but it is
/// recorded, because the symptom — last session's picked files staying on disk
/// — is otherwise invisible.
///
/// Both outcomes need handling. The plugin reports a failed delete by
/// *resolving* with `false`, and with `null` when Android has no attached
/// activity; only a channel-level fault (`MissingPluginException`, a
/// `PlatformException`) arrives as a throw. On a device cold start the call
/// resolved `true`, so the `null` case is handled rather than expected.
void _clearFilePickerTempCacheOnMobile() {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  final logger = LogManager.instance.getLogger('soliplex.shell');
  unawaited(
    FilePicker.clearTemporaryFiles().then((cleared) {
      if (cleared != true) {
        logger.warning(
          'The file picker temp cache was not cleared (result: $cleared)',
        );
      }
    }).catchError((Object error, StackTrace stack) {
      // With the trace: for a MissingPluginException or a TypeError out of the
      // plugin path it is the only thing naming where the throw came from.
      logger.warning(
        'Failed to clear the file picker temp cache',
        error: error,
        stackTrace: stack,
      );
    }),
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
        statusMessageConfigProvider
            .overrideWithValue(widget.config.statusMessage),
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
  late final InactivityMonitor? _monitor = ref.read(inactivityMonitorProvider);

  @override
  void initState() {
    super.initState();
    if (_monitor != null) {
      // HardwareKeyboard sees every key the framework receives,
      // regardless of which widget owns focus — a root `Focus` widget
      // would miss keys consumed by descendants like `TextField`.
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
    if (_monitor != null) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _monitor?.bumpActivity();
    return false;
  }

  void _onPointer(PointerEvent _) => _monitor?.bumpActivity();

  @override
  Widget build(BuildContext context) {
    final monitor = _monitor;
    final app = MaterialApp.router(
      title: widget.config.appName,
      theme: widget.config.lightTheme,
      darkTheme: widget.config.darkTheme,
      themeMode: widget.config.themeMode,
      routerConfig: widget.router,
      builder: monitor == null
          ? null
          : (context, child) => InactivityDialogHost(
                monitor: monitor,
                navigatorKey: widget.router.routerDelegate.navigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
    );
    if (monitor == null) return app;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      // `onPointerSignal` fires on trackpad/wheel scroll on desktop and
      // web. On mobile, scrolling is a drag gesture starting with
      // `onPointerDown`. Bare cursor movement/hover (`onPointerHover`/
      // `onPointerMove` with no button) is intentionally NOT counted as
      // activity — presence of the cursor isn't engagement, and counting
      // it would defeat inactivity detection on desktop/web.
      onPointerSignal: _onPointer,
      child: app,
    );
  }
}
