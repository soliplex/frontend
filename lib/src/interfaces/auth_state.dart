import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class AuthState {
  const AuthState();
}

final class Authenticated extends AuthState {
  const Authenticated();
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final authStateProvider = Provider<AuthState>(
  (_) => throw UnimplementedError(
      'authStateProvider must be overridden by a module'),
);
