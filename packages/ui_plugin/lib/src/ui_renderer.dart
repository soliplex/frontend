/// Embedder-provided renderer that [UiPlugin] delegates all visible effects to.
///
/// Implementations live outside this package (e.g. `SoliplexUiRenderer` in
/// `ui_renderer_soliplex`). Tests supply [FakeUiRenderer]. The plugin
/// constructor requires a concrete instance — there is no null renderer path.
abstract class UiRenderer {
  /// Show a blocking modal with a [title], [body] text, and optional [actions].
  ///
  /// [actions] is a list of button labels (e.g. `['Got it', 'Learn more']`).
  /// Defaults to a single dismiss button when null or empty.
  ///
  /// Resolves to the label of the tapped action, or `null` if dismissed via
  /// the backdrop or back gesture.
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  });

  /// Show a blocking form described by [schema].
  ///
  /// Resolves to the user's field submissions as a plain map, or `null` if the
  /// form was dismissed without submitting.
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  });

  /// Pop a non-blocking toast notification.
  ///
  /// [kind] is one of `'info'`, `'success'`, `'warning'`, `'error'`.
  /// Never blocks; renderer owns the dismiss timing.
  void notify({
    required String kind,
    required String title,
    String? body,
  });

  /// Inject an ephemeral, client-only message into the active chat area.
  ///
  /// The message is visually distinct from real assistant turns (different
  /// background, plugin icon). It is not sent to the server and disappears
  /// on reload or navigation.
  ///
  /// [format] is `'markdown'` (default) or `'plain'`.
  void injectMessage({required String content, String? format});

  /// Request user confirmation for a verb applied to an optional [target].
  ///
  /// Returns `true` if approved, `false` if denied. Never throws for a user
  /// denial — that is a valid outcome, not an error.
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  });
}
