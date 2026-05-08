import 'package:soliplex_logging/soliplex_logging.dart';

/// Returns a logger suitable for tests that don't care about the logger
/// dependency. Backed by the shared `LogManager` so logs route to the
/// in-memory test sink rather than the network.
Logger testLogger([String name = 'test']) =>
    LogManager.instance.getLogger(name);
