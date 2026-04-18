/// Reactive state of the [UiPlugin].
///
/// Subscribers (debug panels, telemetry, activity feed) observe
/// [UiPlugin.stateSignal] to track UI surface lifecycle without polling.
sealed class UiSessionState {
  const UiSessionState();
}

/// No UI surface is currently active.
final class UiIdle extends UiSessionState {
  const UiIdle();
}

/// A blocking confirmation dialog is open.
final class UiAwaitingConfirm extends UiSessionState {
  const UiAwaitingConfirm({
    required this.verb,
    required this.message,
    this.target,
  });

  final String verb;
  final String message;
  final String? target;
}

/// A blocking modal (dismiss-only or simple buttons) is open.
final class UiModalOpen extends UiSessionState {
  const UiModalOpen({required this.title});

  final String title;
}

/// A blocking form is open awaiting user input.
final class UiFormOpen extends UiSessionState {
  const UiFormOpen({required this.schemaKey});

  /// Opaque key derived from the schema (e.g. a hash). Full schema stays
  /// internal to the plugin; observers use this for identity checks only.
  final String schemaKey;
}
