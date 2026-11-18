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

/// Shows the system bars [enterFullscreen] hid.
void leaveFullscreen() => _setSystemUiMode(SystemUiMode.edgeToEdge);

/// Only iOS and Android have system bars to hide.
void _setSystemUiMode(SystemUiMode mode) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  unawaited(SystemChrome.setEnabledSystemUIMode(mode));
}
