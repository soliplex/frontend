import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory, session-scoped record of dismissed status messages.
///
/// Keyed by `(serverKey, messageId)` so dismissing one message does not
/// suppress a different, newly-posted message on the same server. Not
/// persisted: it resets on app restart and is cleared via [clear] when a server
/// (re)connects — after a login or a no-auth add — so a re-login re-surfaces a
/// message dismissed earlier in the session.
class StatusMessageDismissals {
  // Records key structurally, so a (serverKey, messageId) pair can never
  // collide with a different pair — no delimiter to be ambiguous about.
  final Set<(String, String)> _keys = <(String, String)>{};

  bool isDismissed(String serverKey, String messageId) =>
      _keys.contains((serverKey, messageId));

  void markDismissed(String serverKey, String messageId) =>
      _keys.add((serverKey, messageId));

  void clear({String? serverKey}) {
    if (serverKey == null) {
      _keys.clear();
      return;
    }
    _keys.removeWhere((k) => k.$1 == serverKey);
  }
}

/// Session-lived store shared across every mounted banner.
final statusMessageDismissalsProvider = Provider<StatusMessageDismissals>(
  (_) => StatusMessageDismissals(),
);
