import 'dart:async';

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:soliplex_agent/soliplex_agent.dart';

/// An in-flight tool approval request waiting for a user decision.
@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
    required this.rationale,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String rationale;

  static const _argsEquality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApprovalRequest &&
          toolCallId == other.toolCallId &&
          toolName == other.toolName &&
          rationale == other.rationale &&
          _argsEquality.equals(arguments, other.arguments);

  @override
  int get hashCode => Object.hash(
        toolCallId,
        toolName,
        rationale,
        _argsEquality.hash(arguments),
      );
}

/// A [ToolApprovalExtension] that surfaces tool approval requests as reactive
/// state so the UI can respond via a signal-driven dialog.
///
/// When [AgentSession.requestApproval] fires, [stateSignal] is set to the
/// pending [ApprovalRequest]. The UI watches the signal, shows an approval
/// dialog, then calls [respond] with the user's decision. Calling [respond]
/// clears the signal back to `null` and resolves the session's future.
///
/// If the session is cancelled or the extension is disposed while an approval
/// is pending, the request is automatically denied and the signal cleared.
class HumanApprovalExtension extends ToolApprovalExtension
    with StatefulSessionExtension<ApprovalRequest?> {
  HumanApprovalExtension() {
    setInitialState(null);
  }

  ({ApprovalRequest req, Completer<bool> resp})? _pending;

  @override
  int get priority => 30;

  @override
  List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {
    unawaited(session.cancelToken.whenCancelled.then((_) => _denyPending()));
  }

  @override
  void onDispose() {
    _denyPending();
    super.onDispose();
  }

  @override
  Future<bool> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) {
    _denyPending();
    final completer = Completer<bool>();
    _setPending(
      (
        req: ApprovalRequest(
          toolCallId: toolCallId,
          toolName: toolName,
          arguments: arguments,
          rationale: rationale,
        ),
        resp: completer,
      ),
    );
    return completer.future;
  }

  /// Resolves the pending approval request with [approved] and clears state.
  ///
  /// No-op if there is no pending request.
  void respond(bool approved) {
    final p = _pending;
    if (p == null) return;
    p.resp.complete(approved);
    _setPending(null);
  }

  void _setPending(({ApprovalRequest req, Completer<bool> resp})? value) {
    _pending = value;
    state = value?.req;
  }

  void _denyPending() {
    final p = _pending;
    if (p == null) return;
    if (!p.resp.isCompleted) p.resp.complete(false);
    _setPending(null);
  }
}
