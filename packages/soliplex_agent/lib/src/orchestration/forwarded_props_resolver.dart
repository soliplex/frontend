/// Supplies the AG-UI `forwardedProps` for a turn's runs.
///
/// Awaited once when a turn opens, before its first run is created; every run
/// of that turn, including one that resumes after a client tool, sends the
/// same value.
typedef ForwardedPropsResolver = Future<Map<String, dynamic>> Function();
