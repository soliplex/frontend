import 'package:soliplex_client/soliplex_client.dart';

/// What a thread's workspace listing currently shows.
sealed class WorkdirFilesStatus {
  const WorkdirFilesStatus();
}

/// No listing has landed yet.
class WorkdirFilesLoading extends WorkdirFilesStatus {
  const WorkdirFilesLoading();
}

class WorkdirFilesLoaded extends WorkdirFilesStatus {
  const WorkdirFilesLoaded(this.files);

  /// Sorted by filename; the backend lists in directory order.
  final List<WorkdirFile> files;
}

class WorkdirFilesFailed extends WorkdirFilesStatus {
  const WorkdirFilesFailed(this.error, {this.retrying = false});

  final Object error;

  /// Whether a retry is in flight; a retry stays Failed rather than Loading so
  /// the section that offered it stays on screen.
  final bool retrying;
}

/// Fixed user-facing text for a failed listing. Never renders the error's own
/// message: it can carry backend text, URLs or tokens.
String workdirErrorMessage(Object error) {
  if (error is AuthException) return 'Sign in again to see these files.';
  if (error is NetworkException) return "Couldn't reach the server.";
  if (error is ApiException && error.statusCode >= 500) {
    return 'Server is temporarily unavailable.';
  }
  return 'Something went wrong.';
}
