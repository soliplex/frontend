sealed class AuthState {
  const AuthState();
}

final class Authenticated extends AuthState {
  const Authenticated();
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}
