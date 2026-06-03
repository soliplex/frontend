import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import '../auth/return_to_storage.dart';

/// Persists [prompt] so it survives the route guard's redirect on auth
/// expiry.
///
/// Empty / whitespace-only [prompt] is a no-op. Storage failures are
/// logged at SEVERE and swallowed; the user's draft is lost but the
/// redirect still proceeds.
void persistComposerDraft({
  required String serverId,
  required String roomId,
  required String prompt,
}) {
  if (prompt.trim().isEmpty) return;
  unawaited(
    ReturnToStorage.saveComposer(
      serverId: serverId,
      roomId: roomId,
      unsentText: prompt,
    ).catchError((Object e, StackTrace st) {
      dev.log(
        'Failed to persist composer draft for auth roundtrip',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }),
  );
}
