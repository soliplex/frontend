import 'callback_params.dart';
import 'callback_service_native.dart'
    if (dart.library.js_interop) 'callback_service_web.dart'
    as impl;

export 'callback_params.dart';

/// Static utility for capturing OAuth callback params in main().
///
/// Use BEFORE ProviderScope is created to capture URL params that
/// GoRouter might modify.
abstract final class CallbackParamsCapture {
  /// Capture callback params from current URL.
  ///
  /// On web, extracts tokens from URL query params.
  /// On native, returns [NoCallbackParams].
  static CallbackParams captureNow() => impl.captureCallbackParamsNow();
}

/// Clears OAuth callback parameters from the browser URL.
///
/// On web, removes tokens from the URL and browser history.
/// On native, this is a no-op.
void clearCallbackUrl() => impl.clearCallbackUrl();
