// Native is the default; web overrides with a stub since it has no resolver
// API.
import 'host_resolution_native.dart'
    if (dart.library.js_interop) 'host_resolution_web.dart' as platform;

/// Describes whether [host] resolves right now, independently of the HTTP
/// client that just failed to reach it.
///
/// This is the discriminator a "cannot find host" error cannot give on its own.
/// `NSURLErrorCannotFindHost` (-1003) is reported by the URL loading system, so
/// it conflates a genuine resolver failure with anything inside that stack that
/// prevents a lookup from completing. Asking the platform resolver directly
/// separates the two: if the name resolves here while the request failed, the
/// fault is above DNS; if it fails here too, the name genuinely does not
/// resolve for this device on this network.
///
/// Only called on an already-failed probe, and awaited before that failure is
/// returned, so its deadline is a delay the user feels. Held short on purpose:
/// a name that resolves answers in milliseconds, and a resolver that needs
/// longer has already told the record what it needs to say.
Future<String> describeHostResolution(String host) =>
    platform.describeHostResolution(host);
