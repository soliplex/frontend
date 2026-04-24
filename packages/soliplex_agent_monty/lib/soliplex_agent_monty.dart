/// Bridge between `soliplex_agent` and `dart_monty`.
///
/// Wraps a `MontyRuntime` in a `SessionExtension` so Python scripts
/// running in the on-device sandbox integrate with the same session
/// lifecycle and observation surface as the rest of the agent's
/// extensions.
library;

export 'src/monty_extension_set.dart';
export 'src/monty_runtime_extension.dart';
