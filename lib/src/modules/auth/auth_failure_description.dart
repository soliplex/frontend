import 'platform/auth_flow.dart';

/// Maps an [AuthFailureKind] (plus optional context) to user-facing
/// text. Centralised so UI never re-interpolates raw exception fields.
///
/// Never returns the raw [oauthError] string — unknown OAuth codes fall
/// back to a generic retry message. RFC 6749 error codes are
/// developer-jargon and not safe to display.
String describeAuthFailure({
  required AuthFailureKind kind,
  String? oauthError,
  String? serverUrl,
}) {
  switch (kind) {
    case AuthFailureKind.cancelled:
      return 'Sign-in was cancelled.';
    case AuthFailureKind.discoveryUnreachable:
      return serverUrl != null
          ? "Couldn't reach the sign-in server at $serverUrl. "
              'Check your connection and try again.'
          : "Couldn't reach the sign-in server. "
              'Check your connection and try again.';
    case AuthFailureKind.network:
      return 'Network problem during sign-in. Check your connection and try again.';
    case AuthFailureKind.idpRejected:
      return _describeIdpRejection(oauthError);
    case AuthFailureKind.noBrowser:
      return 'No browser is available for sign-in. Install a browser and try again.';
    case AuthFailureKind.unknown:
      return 'Sign-in failed. Please try again.';
  }
}

String _describeIdpRejection(String? oauthError) {
  switch (oauthError) {
    case 'access_denied':
      return 'The identity provider rejected the sign-in request.';
    case 'invalid_grant':
      return 'Your sign-in has expired. Please sign in again.';
    case 'invalid_client':
    case 'unauthorized_client':
      return 'This app is not authorised to sign in with this server. '
          'Contact your administrator.';
    case 'invalid_scope':
      return 'This app requested permissions the server does not allow. '
          'Contact your administrator.';
    default:
      return 'Sign-in was rejected. Please try again.';
  }
}
