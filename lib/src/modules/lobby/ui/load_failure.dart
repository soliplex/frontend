import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        MalformedResponseException,
        NetworkException,
        PermissionDeniedException;

/// A failed load as a person should read it, rather than an exception's
/// `toString()`.
///
/// [retryable] is false for a refusal: asking again gets the same answer,
/// so a Retry button there only reads as a bug.
typedef LoadFailure = ({String detail, bool retryable});

/// Describes [error] from loading [what] (for example "threads").
LoadFailure describeLoadFailure(Object error, {required String what}) {
  return switch (error) {
    PermissionDeniedException() => (
        detail: "You don't have permission to see $what on this server.",
        retryable: false,
      ),
    AuthException() => (
        detail: 'Your session has ended. Sign in again to see $what.',
        retryable: false,
      ),
    NetworkException() => (
        detail: "Can't reach the server. Check your connection.",
        retryable: true,
      ),
    MalformedResponseException() => (
        detail: "The server's answer wasn't in a form this app understands.",
        retryable: true,
      ),
    _ => (
        detail: 'Something went wrong on the server.',
        retryable: true,
      ),
  };
}
