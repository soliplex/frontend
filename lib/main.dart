import 'package:flutter/widgets.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/src/core/log_sinks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // See installLogSinks for where records surface (DevTools Logging vs stdout),
  // what can observe each, and the per-mode level floor.
  installLogSinks(LogManager.instance);
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(await standard(callbackParams: callbackParams));
}
