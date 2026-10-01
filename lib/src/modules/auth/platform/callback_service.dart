import 'callback_params.dart';
import 'callback_service_native.dart'
    if (dart.library.js_interop) 'callback_service_web.dart' as impl;

export 'callback_params.dart';

/// Static utility for capturing OAuth callback params in main().
///
/// Use BEFORE ProviderScope is created to capture URL params that
/// GoRouter might modify.
abstract final class CallbackParamsCapture {
  /// Capture callback params from current URL.
  ///
  /// On web, reads the tokens `web/index.html` moved out of the URL, or the
  /// URL itself when that script is missing.
  /// On native, returns [NoCallbackParams].
  static CallbackParams captureNow() => impl.captureCallbackParamsNow();
}

/// Clears OAuth callback parameters from the browser URL.
///
/// On web, removes every query from the page URL on load, in the address bar
/// and in the hash route, including the sign-in callback's tokens.
/// On native, this is a no-op.
void clearCallbackUrl() => impl.clearCallbackUrl();
