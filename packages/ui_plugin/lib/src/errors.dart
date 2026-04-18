/// Thrown when the [UiRenderer] raises during a plugin handler call.
///
/// The plugin catches renderer errors, transitions state back to [UiIdle], and
/// returns this as an error string to Python (per the project's error-as-output
/// discipline — never throw across the bridge boundary).
class RendererUnavailableError implements Exception {
  const RendererUnavailableError(this.operation, [this.cause]);

  final String operation;
  final Object? cause;

  @override
  String toString() =>
      'RendererUnavailableError[$operation]${cause != null ? ': $cause' : ''}';
}
