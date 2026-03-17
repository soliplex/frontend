import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class AuthState {}

final class Authenticated extends AuthState {}

final class Unauthenticated extends AuthState {}

final authStateProvider = Provider<AuthState>(
  (_) => throw UnimplementedError(),
);
