// Native implementations of the video player's web-only needs, all no-ops.
// The web ones are in video_platform_web.dart.

/// Makes the player's runtime available. Nothing to load on native platforms.
Future<void> ensureVideoRuntime() async {}

/// Asks the browser to show the page fullscreen, calling [onExit] when it
/// stops. Native platforms have no browser fullscreen; the fullscreen page
/// hides the system bars instead.
void enterBrowserFullscreen({required void Function() onExit}) {}

/// Leaves the browser fullscreen [enterBrowserFullscreen] entered, if any.
void exitBrowserFullscreen() {}
