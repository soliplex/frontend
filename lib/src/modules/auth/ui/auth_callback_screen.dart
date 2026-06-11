import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../auth_failure_description.dart';
import '../auth_providers.dart';
import '../auth_tokens.dart';
import '../platform/auth_flow.dart';
import '../platform/callback_params.dart';
import '../pre_auth_state.dart';
import '../server_entry.dart';
import '../server_manager.dart';
import 'home_shell.dart';
import 'package:soliplex_design/soliplex_design.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({
    super.key,
    required this.serverManager,
    this.appName = 'Soliplex',
    this.logo,
  });

  final ServerManager serverManager;
  final String appName;
  final Widget? logo;

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
          dev.log('Auth callback returned OAuth error', error: error);
          _fail(describeAuthFailure(
            kind: AuthFailureKind.idpRejected,
            oauthError: error,
          ));
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
          idToken: params.idToken,
        ),
      );

      // Web: the inactivity flag survived the redirect via storage.
      // Clear it now that a credential-challenged sign-in has completed.
      await ref.read(inactivityLogoutFlagsProvider).clear(serverId);

      if (mounted) context.go(_safeReturnTo(preAuth.frontendReturnTo));
    } catch (e, st) {
      dev.log(
        'Auth callback failed',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _fail('Something went wrong. Please try again.');
    }
  }

  /// Returns [returnTo] if it's a safe relative in-app path, else
  /// falls back to the lobby.
  ///
  /// Defense in depth on top of [PreAuthState]'s constructor
  /// validation: rejects absolute URLs (`http://`, `https://`) and
  /// protocol-relative URLs (`//host/...`) so a tampered storage entry
  /// cannot open-redirect the user even if it bypassed the type
  /// invariant.
  String _safeReturnTo(String? returnTo) {
    if (returnTo == null || returnTo.isEmpty) return AppRoutes.lobby;
    if (returnTo.startsWith('//') ||
        returnTo.startsWith('http://') ||
        returnTo.startsWith('https://')) {
      dev.log(
        'Rejected returnTo (open-redirect target): $returnTo',
        level: 900,
      );
      return AppRoutes.lobby;
    }
    if (!returnTo.startsWith('/')) {
      dev.log(
        'Rejected returnTo (not an absolute path): $returnTo',
        level: 800,
      );
      return AppRoutes.lobby;
    }
    return returnTo;
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
      return HomeShell(
        appName: widget.appName,
        logo: widget.logo,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(SoliplexSpacing.s4),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return HomeShell(
      appName: widget.appName,
      logo: widget.logo,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: SoliplexSpacing.s4),
          Text(
            _error ?? 'An error occurred',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          SoliplexButton.filled(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}
