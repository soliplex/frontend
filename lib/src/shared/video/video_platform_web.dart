import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:web/web.dart' as web;

import 'video_playback.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.video');

/// Where the build serves Shaka Player 4.16.56, which `better_player` plays
/// through on the web. Vendored (Apache-2.0) rather than loaded from a CDN, so
/// a deployment that cannot reach one, or whose content security policy
/// forbids it, still plays video. An app built on this library serves it from
/// its own `web/vendor/`.
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
  late final Timer limit;
  void failed(String why) {
    limit.cancel();
    if (loaded.isCompleted) return;
    // Forget the failed load, so the next video tries again.
    _shakaLoad = null;
    script.remove();
    loaded.completeError(VideoPlaybackException('$why from $_shakaScript'));
  }

  // A request the server accepts and never finishes fires neither event.
  limit = Timer(
    videoStartLimit,
    () => failed(
      'the video player did not load within '
      '${videoStartLimit.inSeconds} seconds',
    ),
  );

  script
    ..addEventListener(
      'load',
      ((web.Event _) {
        // A host that answers a missing file with its index page still
        // "loads" it, and defines nothing.
        if (globalContext.has('shaka')) {
          limit.cancel();
          if (!loaded.isCompleted) loaded.complete();
        } else {
          failed('the video player was not defined by the script');
        }
      }).toJS,
    )
    ..addEventListener(
      'error',
      ((web.Event _) => failed('could not load the video player')).toJS,
    );
  web.document.head!.append(script);
  return loaded.future;
}

web.EventListener? _fullscreenListener;

/// Asks the browser to show the page fullscreen, calling [onExit] when the
/// user leaves it: Escape, or the browser's own control. [leaveFullscreen]
/// leaves without calling it.
///
/// Must run inside the user's tap, which is what lets a page go fullscreen. A
/// refusal, or a browser that cannot, is logged and otherwise ignored: the
/// fullscreen page still fills the window.
void enterFullscreen({required void Function() onExit}) {
  _stopListening();
  final page = web.document.documentElement!;
  // iPhone Safari lets only a <video> element go fullscreen.
  if (!page.has('requestFullscreen')) {
    _logger.info('The browser cannot show the page fullscreen');
    return;
  }
  final listener = ((web.Event _) {
    if (web.document.fullscreenElement != null) return;
    _stopListening();
    onExit();
  }).toJS;
  _fullscreenListener = listener;
  web.document.addEventListener('fullscreenchange', listener);
  unawaited(
    page.requestFullscreen().toDart.then(
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

/// Leaves the browser fullscreen [enterFullscreen] entered, if any, without
/// calling its `onExit`.
void leaveFullscreen() {
  _stopListening();
  if (web.document.fullscreenElement != null) {
    // A refusal leaves the page fullscreen, which the user can still leave
    // with Escape. Like a refusal to enter, it is a DOMException naming why.
    unawaited(
      web.document.exitFullscreen().toDart.then(
            (_) {},
            onError: (Object error) => _logger
                .info('The browser did not leave fullscreen', error: error),
          ),
    );
  }
}

void _stopListening() {
  final listener = _fullscreenListener;
  if (listener == null) return;
  web.document.removeEventListener('fullscreenchange', listener);
  _fullscreenListener = null;
}
