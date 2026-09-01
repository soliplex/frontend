import 'package:flutter/widgets.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // See installLogSinks for where records surface (DevTools Logging vs stdout),
  // what can observe each, and the per-mode level floor.
  installLogSinks();
  // After the sinks, not before: without one, LogManager discards the record.
  installUncaughtErrorLogging();
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  // The builder runs inside runSoliplexShell so a configuration failure
  // reaches the screen rather than stalling the launch.
  await runSoliplexShell(() => standard(callbackParams: callbackParams));
}
