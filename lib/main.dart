import 'package:flutter/widgets.dart';

import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';
import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

/// Compile-time flag gating the on-device Python runtime.
///
/// Build the monty-enabled variant with:
///
/// ```sh
/// flutter build macos --dart-define=MONTY_ENABLED=true
/// ```
///
/// When `false` (default), `MontyRuntimeExtension` is never constructed
/// and the `dart_monty` bytes tree-shake out of the release binary.
const _montyEnabled = bool.fromEnvironment(
  'MONTY_ENABLED',
  // ignore: avoid_redundant_argument_values
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(
    await standard(
      callbackParams: callbackParams,
      extraExtensions: () async => [
        if (_montyEnabled)
          MontyRuntimeExtension(extensions: MontyExtensionSet.standard()),
      ],
    ),
  );
}
