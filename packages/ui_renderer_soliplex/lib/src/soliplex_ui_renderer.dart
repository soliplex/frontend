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
/// [injectedMessages] is a reactive signal — consumers (e.g.
/// [computeDisplayMessages]) subscribe to it to render ephemeral
/// client-only messages inline in the chat area.
class SoliplexUiRenderer implements UiRenderer {
  SoliplexUiRenderer({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  })  : _navigatorKey = navigatorKey,
        _scaffoldMessengerKey = scaffoldMessengerKey;

  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  final Signal<List<InjectedMessage>> _injectedMessages = signal(const []);
  ReadonlySignal<List<InjectedMessage>> get injectedMessages =>
      _injectedMessages;

  int _messageCounter = 0;

  BuildContext? get _context => _navigatorKey.currentContext;
  ScaffoldMessengerState? get _messenger => _scaffoldMessengerKey.currentState;

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
    final id = 'injected_${_messageCounter++}';
    _injectedMessages.value = [
      ..._injectedMessages.value,
      InjectedMessage(
        id: id,
        content: content,
        format: format ?? 'markdown',
        createdAt: DateTime.now(),
      ),
    ];
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

  /// Remove all injected messages (e.g. on navigation or session end).
  void clearInjectedMessages() => _injectedMessages.value = const [];
}
