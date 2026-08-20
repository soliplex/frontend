import 'dart:async' show unawaited;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/return_to_storage.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.composer_persistence');

/// Persists [draft] so it survives the route guard's redirect on auth
/// expiry. Build it with `encodeComposerDraft`, which keeps every image's
/// position and none of its bytes.
///
/// Empty / whitespace-only [draft] is a no-op. Storage failures are
/// logged at SEVERE and swallowed; the user's draft is lost but the
/// redirect still proceeds.
void persistComposerDraft({
  required String serverId,
  required String? userId,
  required String roomId,
  required String draft,
}) {
  if (draft.trim().isEmpty) return;
  unawaited(
    ReturnToStorage.saveComposer(
      serverId: serverId,
      userId: userId,
      roomId: roomId,
      unsentText: draft,
    ).catchError((Object e, StackTrace st) {
      _logger.error(
        'Failed to persist composer draft for auth roundtrip',
        error: e,
        stackTrace: st,
      );
    }),
  );
}
