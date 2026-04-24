// dart_monty's public barrel currently has a broken re-export and
// does not expose the bundled extension set. Until that's fixed
// upstream, import the needed types directly from their implementation
// files. The alternative barrel `dart_monty_bridge.dart` also works but
// is named for internal bridge-layer use; prefer the specific imports.
// ignore_for_file: implementation_imports
import 'package:dart_monty/src/extension/extension.dart' show MontyExtension;
import 'package:dart_monty/src/extensions/defaults.dart' show defaultExtensions;

/// Named collection of `dart_monty` extensions to load into a
/// `MontyRuntime` instance bridged by `MontyRuntimeExtension`.
///
/// Exists as a typed wrapper (rather than a bare `List<MontyExtension>`)
/// so future tiers — `.withSandbox`, `.withDatabase`, etc. — slot in
/// without changing the bridge API.
class MontyExtensionSet {
  const MontyExtensionSet(this.all);

  /// Config-free, cross-backend default set from `dart_monty`'s
  /// `defaultExtensions()`: Jinja templating, message bus, and event
  /// loop. No filesystem, no subprocesses, no platform-specific
  /// extensions.
  factory MontyExtensionSet.standard() =>
      MontyExtensionSet(defaultExtensions());

  /// The extensions to pass to `MontyRuntime`'s `extensions` parameter.
  final List<MontyExtension> all;
}
