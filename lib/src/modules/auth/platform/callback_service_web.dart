import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'callback_params.dart';
import 'callback_params_parser.dart';

/// Captures callback params from current URL.
CallbackParams captureCallbackParamsNow() {
  final params = extractQueryParams(
    search: web.window.location.search,
    hash: web.window.location.hash,
  );
  return parseCallbackParams(params);
}

/// Clears OAuth callback parameters from the browser URL.
void clearCallbackUrl() {
  final origin = web.window.location.origin;
  final pathname = web.window.location.pathname;
  var hash = web.window.location.hash;

  if (hash.isNotEmpty) {
    final queryIndex = hash.indexOf('?');
    if (queryIndex != -1) {
      hash = hash.substring(0, queryIndex);
    }
  }

  final cleanUrl = '$origin$pathname$hash';
  web.window.history.replaceState(JSObject(), '', cleanUrl);
}
