import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:web/web.dart' as web;

final _logger = LogManager.instance.getLogger('soliplex_frontend.video');

/// Where the build serves Shaka Player, which `better_player` plays through on
/// the web. Vendored (Apache-2.0, version in the file's header) rather than
/// loaded from a CDN, so a deployment that cannot reach one, or whose content
/// security policy forbids it, still plays video.
const _shakaScript = 'vendor/shaka-player.compiled.js';

Future<void>? _shakaLoad;

/// Loads Shaka Player the first time a video is played, so a session that
/// never plays one never downloads it.
Future<void> ensureVideoRuntime() {
  if (globalContext.has('shaka')) return Future.value();
  return _shakaLoad ??= _loadShaka();
}

Future<void> _loadShaka() {
  final loaded = Completer<void>();
  final script = web.HTMLScriptElement()..src = _shakaScript;
  script
    ..addEventListener(
      'load',
      ((web.Event _) => loaded.complete()).toJS,
    )
    ..addEventListener(
      'error',
      ((web.Event _) {
        // Forget the failed load, so the next video tries again.
        _shakaLoad = null;
        script.remove();
        loaded.completeError(
          StateError('could not load the video player from $_shakaScript'),
        );
      }).toJS,
    );
  web.document.head!.append(script);
  return loaded.future;
}

web.EventListener? _fullscreenListener;

/// Asks the browser to show the page fullscreen, calling [onExit] when it
/// stops: Escape, the browser's own control, or [exitBrowserFullscreen].
///
/// Must run inside the user's tap, which is what lets a page go fullscreen. A
/// refusal is logged and otherwise ignored: the fullscreen page still fills the
/// window.
void enterBrowserFullscreen({required void Function() onExit}) {
  _stopListening();
  final listener = ((web.Event _) {
    if (web.document.fullscreenElement != null) return;
    _stopListening();
    onExit();
  }).toJS;
  _fullscreenListener = listener;
  web.document.addEventListener('fullscreenchange', listener);
  unawaited(
    web.document.documentElement!.requestFullscreen().toDart.then(
      (_) {},
      onError: (Object error) {
        _stopListening();
        // The rejection is a DOMException naming why (no user gesture, a
        // policy); it carries no URL or value of ours.
        _logger.info('The browser refused fullscreen', error: error);
      },
    ),
  );
}

/// Leaves the browser fullscreen [enterBrowserFullscreen] entered, if any,
/// without calling its `onExit`.
void exitBrowserFullscreen() {
  _stopListening();
  if (web.document.fullscreenElement != null) {
    // A refusal leaves the page fullscreen, which the user can still leave
    // with Escape; there is nothing better to do with it.
    unawaited(
      web.document.exitFullscreen().toDart.then((_) {}, onError: (_) {}),
    );
  }
}

void _stopListening() {
  final listener = _fullscreenListener;
  if (listener == null) return;
  web.document.removeEventListener('fullscreenchange', listener);
  _fullscreenListener = null;
}
