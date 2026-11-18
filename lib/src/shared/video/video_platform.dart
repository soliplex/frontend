import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Native implementations of what the video player does differently on the
// web. The web ones are in video_platform_web.dart.

/// Makes the player's runtime available. Nothing to load on native platforms.
Future<void> ensureVideoRuntime() async {}

/// Hides the system bars for the fullscreen page, where the system allows:
/// Flutter documents `immersive` as ignored by Android for an app that
/// targets API 36, as this one does. [onExit] goes unused:
/// natively the page is left only by its exit button or the back gesture,
/// both of which pop it.
void enterFullscreen({required void Function() onExit}) =>
    _setSystemUiMode(SystemUiMode.immersive);

/// Shows the system bars [enterFullscreen] hid, as the app started with them:
/// both shown, which on Android is the embedding's starting state on every
/// version. `edgeToEdge` is not: it does nothing below Android 10, leaving
/// the bars hidden.
void leaveFullscreen() => _setSystemUiMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

/// Only iOS and Android have system bars to hide.
void _setSystemUiMode(SystemUiMode mode, {List<SystemUiOverlay>? overlays}) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  unawaited(SystemChrome.setEnabledSystemUIMode(mode, overlays: overlays));
}
