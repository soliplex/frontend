import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:ui_plugin/ui_plugin.dart';

import 'widgets/ui_confirm_dialog.dart';
import 'widgets/ui_form_dialog.dart';
import 'widgets/ui_modal_dialog.dart';

/// Flutter implementation of [UiRenderer] for the Soliplex app.
///
/// Requires a [GlobalKey<NavigatorState>] (for dialog routing) and a
/// [GlobalKey<ScaffoldMessengerState>] (for SnackBar toasts). Both are
/// wired into [MaterialApp.router] via [ShellConfig].
///
/// Use [messagesForRoom] to get a per-room reactive signal of ephemeral
/// messages. Pass [RoomScopedUiRenderer] to [UiPlugin] so each room's
/// messages are stored separately.
class SoliplexUiRenderer implements UiRenderer {
  SoliplexUiRenderer({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  })  : _navigatorKey = navigatorKey,
        _scaffoldMessengerKey = scaffoldMessengerKey;

  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  final Map<String, Signal<List<InjectedMessage>>> _roomMessages = {};
  int _messageCounter = 0;

  BuildContext? get _context => _navigatorKey.currentContext;
  ScaffoldMessengerState? get _messenger => _scaffoldMessengerKey.currentState;

  // ---------------------------------------------------------------------------
  // Scoped message storage
  //
  // The scope key can be at any granularity:
  //   room level:   '$serverId:$roomId'
  //   thread level: '$serverId:$roomId:$threadId'
  //
  // Callers choose the key; the renderer stores and retrieves by exact match.
  // ---------------------------------------------------------------------------

  Signal<List<InjectedMessage>> _signalFor(String scopeKey) =>
      _roomMessages.putIfAbsent(scopeKey, () => signal(const []));

  /// Returns the reactive message list for [scopeKey].
  ///
  /// Creates an empty signal the first time [scopeKey] is seen. Always returns
  /// the same signal object for the same key, so [watch] subscriptions survive
  /// across rebuilds.
  ReadonlySignal<List<InjectedMessage>> messagesFor(String scopeKey) =>
      _signalFor(scopeKey);

  /// Injects an ephemeral message into [scopeKey]'s message list.
  void injectMessageFor(
    String scopeKey, {
    required String content,
    String? format,
  }) {
    final sig = _signalFor(scopeKey);
    final id = 'injected_${_messageCounter++}';
    sig.value = [
      ...sig.value,
      InjectedMessage(
        id: id,
        content: content,
        format: format ?? 'markdown',
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Clears all injected messages for [scopeKey].
  void clearMessagesFor(String scopeKey) {
    _roomMessages[scopeKey]?.value = const [];
  }

  /// Clears injected messages for every scope.
  void clearAllMessages() {
    for (final sig in _roomMessages.values) {
      sig.value = const [];
    }
  }

  // ---------------------------------------------------------------------------
  // UiRenderer — modals / toasts / confirm
  // ---------------------------------------------------------------------------

  @override
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  }) async {
    final ctx = _context;
    if (ctx == null) return null;
    return UiModalDialog.show(
      context: ctx,
      title: title,
      body: body,
      actions: actions,
    );
  }

  @override
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  }) async {
    final ctx = _context;
    if (ctx == null) return null;
    return UiFormDialog.show(
      context: ctx,
      title: 'Form',
      schema: schema,
    );
  }

  @override
  void notify({required String kind, required String title, String? body}) {
    final messenger = _messenger;
    if (messenger == null) return;

    final color = switch (kind) {
      'success' => Colors.green.shade700,
      'warning' => Colors.orange.shade700,
      'error' => Colors.red.shade700,
      _ => null,
    };

    messenger.showSnackBar(
      SnackBar(
        content: body != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(body),
                ],
              )
            : Text(title),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void injectMessage({required String content, String? format}) {
    // Called when UiPlugin is not scoped. Use a fallback key so messages
    // still appear (they'll be visible in any scope watching '_default').
    injectMessageFor('_default', content: content, format: format);
  }

  @override
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  }) async {
    final ctx = _context;
    if (ctx == null) return false;
    return UiConfirmDialog.show(
      context: ctx,
      verb: verb,
      message: message,
      target: target,
    );
  }
}

// ---------------------------------------------------------------------------
// RoomScopedUiRenderer
// ---------------------------------------------------------------------------

/// A [UiRenderer] wrapper that scopes [injectMessage] to a specific scope key.
///
/// Pass one of these to each [UiPlugin] created inside `buildEnv` so that
/// Python's `ui_inject_message` calls are stored under the given scope key
/// and only shown in the matching view.
///
/// The scope key can be at any granularity:
///   - room level:   `'$serverId:$roomId'`
///   - thread level: `'$serverId:$roomId:$threadId'`
///
/// All other renderer operations (modals, toasts, confirm) are delegated to
/// the underlying [SoliplexUiRenderer] unchanged — they are app-level
/// interactions that don't need scope isolation.
class RoomScopedUiRenderer implements UiRenderer {
  /// Creates a renderer scoped to [scopeKey] backed by [base].
  RoomScopedUiRenderer(this._base, this.scopeKey);

  final SoliplexUiRenderer _base;

  /// The scope key this renderer injects messages under.
  final String scopeKey;

  @override
  void injectMessage({required String content, String? format}) =>
      _base.injectMessageFor(scopeKey, content: content, format: format);

  @override
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  }) =>
      _base.showModal(title: title, body: body, actions: actions);

  @override
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  }) =>
      _base.showForm(schema: schema);

  @override
  void notify({
    required String kind,
    required String title,
    String? body,
  }) =>
      _base.notify(kind: kind, title: title, body: body);

  @override
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  }) =>
      _base.requestConfirm(verb: verb, message: message, target: target);
}
