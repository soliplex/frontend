import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../auth_providers.dart';
import '../auth_tokens.dart';
import '../platform/callback_params.dart';
import '../pre_auth_state.dart';
import '../server_entry.dart';
import '../server_manager.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key, required this.serverManager});

  final ServerManager serverManager;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;
  bool _processing = true;

  @override
  void initState() {
    super.initState();
    _processCallback();
  }

  Future<void> _processCallback() async {
    try {
      final params = ref.read(callbackParamsProvider);

      switch (params) {
        case NoCallbackParams():
          _fail('No callback parameters received.');
          return;
        case WebCallbackError(:final error):
          _fail('Authentication failed: $error');
          return;
        case WebCallbackSuccess():
          break;
      }

      final accessToken = params.accessToken;

      final preAuth = await PreAuthStateStorage.load();
      if (!mounted) return;
      if (preAuth == null) {
        _fail('Authentication session expired or missing. Please try again.');
        return;
      }

      await PreAuthStateStorage.clear();
      if (!mounted) return;

      final serverId = serverIdFromUrl(preAuth.serverUrl);
      final entry = widget.serverManager.addServer(
        serverId: serverId,
        serverUrl: preAuth.serverUrl,
      );

      entry.auth.login(
        provider: OidcProvider(
          discoveryUrl: preAuth.discoveryUrl,
          clientId: preAuth.clientId,
        ),
        tokens: AuthTokens(
          accessToken: accessToken,
          refreshToken: params.refreshToken ?? '',
          expiresAt: params.expiresIn != null
              ? DateTime.now().add(Duration(seconds: params.expiresIn!))
              : DateTime.now().add(AuthTokens.defaultLifetime),
          idToken: null,
        ),
      );

      if (mounted) context.go(AppRoutes.lobby);
    } catch (e, st) {
      dev.log('Auth callback failed', error: e, stackTrace: st);
      _fail('Something went wrong. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_processing && _error == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error ?? 'An error occurred'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
