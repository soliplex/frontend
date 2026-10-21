/// Supplies the AG-UI `forwardedProps` for a turn's runs.
///
/// Read once when a turn opens; every run of that turn, including one that
/// resumes after a client tool, sends the same value.
typedef ForwardedPropsResolver = Map<String, dynamic> Function();
