import 'package:dart_monty_flutter/dart_monty_flutter.dart';
import 'package:flutter/widgets.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/flavors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the Monty WASM bridge on web (no-op on native).
  // Throws StateError at startup if the bridge JS cannot be loaded —
  // fails loudly before runApp rather than silently at first use.
  await DartMontyFlutter.ensureInitialized();
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(await standard(callbackParams: callbackParams));
}
