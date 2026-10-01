import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:web/web.dart' as web;

import 'callback_params.dart';
import 'callback_params_parser.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.auth_callback');

/// Where `web/index.html` leaves the callback query it moved out of the URL.
const _stashKey = 'soliplexCallbackQuery';

/// Captures the sign-in callback, from the `web/index.html` stash or, when the
/// script is missing, from the URL.
CallbackParams captureCallbackParamsNow() {
  final key = _stashKey.toJS;
  final stashed = globalContext.getProperty<JSString?>(key)?.toDart;
  globalContext.delete(key);
  final captured = captureCallback(
    stashedQuery: stashed,
    hash: web.window.location.hash,
  );
  if (captured.scriptMissing) {
    _logger.error(
      'Sign-in callback reached the app still in the URL: web/index.html '
      'lacks the callback script (see docs/authoring-a-flavor.md)',
    );
  }
  return captured.params;
}

/// Removes every query from the page URL on load, in the address bar and in
/// the hash route, including the sign-in callback's tokens.
void clearCallbackUrl() {
  final location = web.window.location;
  final url = urlWithoutQueries(
    origin: location.origin,
    pathname: location.pathname,
    search: location.search,
    hash: location.hash,
  );
  if (url == null) return;
  web.window.history.replaceState(JSObject(), '', url);
}
