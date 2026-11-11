import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        NetworkException,
        NotFoundException,
        PermissionDeniedException,
        SoliplexApi,
        ThreadInfo;
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_properties');

/// What a properties save left behind.
///
/// [thread] is the thread as it now stands on the server, for the caller
/// to fold into its list, or `null` when nothing was written. [error] is a
/// sentence for the dialog, or `null` on success. Both are set when the
/// name and description were saved but the labels were not.
typedef ThreadPropertiesSaved = ({ThreadInfo? thread, String? error});

/// Reads [held] again from the server, for a properties dialog to start
/// from.
///
/// A row can be older than the thread: the room inserts a placeholder for
/// a thread it has just started, and the assistant names and labels a
/// thread after its first run. Editing the old copy would put its blank
/// name and missing labels back. Falls back to [held] when the read fails,
/// so the dialog still opens.
Future<ThreadInfo> currentThreadProperties(
  SoliplexApi api,
  ThreadInfo held, {
  required void Function(AuthException error) onAuthFailure,
}) async {
  try {
    final fresh = await api.getThread(held.roomId, held.id);
    // Only what the dialog edits: this read carries no activity time, and
    // the held row's is the one the listing sorts by.
    return held.copyWith(
      name: fresh.name,
      description: fresh.description,
      labels: fresh.labels,
    );
  } on Exception catch (error, st) {
    if (error is AuthException) onAuthFailure(error);
    // What this catch can see is the client's own exceptions over a
    // thread read: status codes, the server's reason, and network errors
    // naming the host. None carries a credential.
    _logger.warning(
      'Could not re-read thread ${held.id} before editing it',
      error: error,
      stackTrace: st,
    );
    return held;
  }
}

/// Saves a thread's name, description and labels, from a properties
/// dialog in the lobby or in a room.
///
/// [initialLabelIds] is what the dialog started from. The labels are sent
/// as that edit applied to the thread's labels on the server now, not as
/// the dialog's whole set: the assistant may have labelled the thread
/// since the dialog's copy was read, and a deleted label is no longer on
/// the server's copy, so neither a label the user never saw nor one that
/// no longer exists is sent back.
///
/// An empty description is sent as `null`. The server replaces the whole
/// metadata record and drops a field sent as `null`, which leaves the
/// thread as it was before anyone described it.
///
/// Never throws an [Exception]: a failure comes back as the record's
/// `error`.
Future<ThreadPropertiesSaved> saveThreadProperties(
  SoliplexApi api,
  ThreadInfo thread, {
  required String name,
  required String description,
  required Set<int> initialLabelIds,
  required Set<int> labelIds,
  required void Function(AuthException error) onAuthFailure,
}) async {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return (thread: null, error: 'A thread needs a name.');
  }
  final trimmedDescription = description.trim();

  try {
    await api.updateThreadMetadata(
      thread.roomId,
      thread.id,
      name: trimmedName,
      description: trimmedDescription.isEmpty ? null : trimmedDescription,
    );
  } on Exception catch (error, st) {
    return (
      thread: null,
      error: _reason(error, st, onAuthFailure, part: 'metadata'),
    );
  }

  final renamed =
      thread.copyWith(name: trimmedName, description: trimmedDescription);

  try {
    final added = labelIds.difference(initialLabelIds);
    final removed = initialLabelIds.difference(labelIds);
    final onServer = await _serverLabelIds(api, thread, initialLabelIds);
    final updated = await api.setThreadLabels(
      thread.roomId,
      thread.id,
      labelIds: {...onServer.difference(removed), ...added}.toList(),
    );
    return (thread: renamed.copyWith(labels: updated.labels), error: null);
  } on Exception catch (error, st) {
    // The name and description are saved; say so, so a retry reads as
    // finishing the job rather than starting it again.
    final reason = error is NotFoundException
        ? 'A label you picked no longer exists. Remove it and save again.'
        : _reason(error, st, onAuthFailure, part: 'labels');
    return (
      thread: renamed,
      error: 'Saved the name and description, but not the labels. $reason',
    );
  }
}

/// The thread's label ids on the server now, or [fallback] when they
/// can't be read.
Future<Set<int>> _serverLabelIds(
  SoliplexApi api,
  ThreadInfo thread,
  Set<int> fallback,
) async {
  try {
    final current = await api.getThread(thread.roomId, thread.id);
    return {for (final label in current.labels) label.id};
  } on Exception catch (error, st) {
    if (error is AuthException) rethrow;
    _logger.warning(
      'Could not re-read thread ${thread.id}; saving its labels from the '
      "dialog's copy",
      error: error,
      stackTrace: st,
    );
    return fallback;
  }
}

/// A sentence a person can act on, for a write that failed.
String _reason(
  Exception error,
  StackTrace st,
  void Function(AuthException error) onAuthFailure, {
  required String part,
}) {
  // A refusal the user can't fix by retrying is expected, not a fault.
  final expected = error is AuthException ||
      error is PermissionDeniedException ||
      error is NotFoundException;
  // What this catch can see is the client's own exceptions over a thread
  // write: status codes, the server's reason, and network errors naming
  // the host. None carries a credential.
  if (expected) {
    _logger.warning('Saving thread $part was refused', error: error);
  } else {
    _logger.error('Saving thread $part failed', error: error, stackTrace: st);
  }

  return switch (error) {
    AuthException() => () {
        onAuthFailure(error);
        return 'Your session has ended. Sign in again, then save.';
      }(),
    PermissionDeniedException() =>
      "You don't have permission to change this thread.",
    NotFoundException() => 'This thread no longer exists.',
    NetworkException() => "Can't reach the server. Check your connection "
        'and try again.',
    _ => 'Could not save the thread. Please try again.',
  };
}
