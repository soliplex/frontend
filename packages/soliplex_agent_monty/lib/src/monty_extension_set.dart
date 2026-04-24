import 'package:dart_monty/dart_monty_bridge.dart'
    show MontyExtension, defaultExtensions;

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
