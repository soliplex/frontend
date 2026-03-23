import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_agent/soliplex_agent.dart' as agent show AuthException;

import '../auth_providers.dart';
import '../default_backend_url.dart';
import '../auth_tokens.dart';
import '../connection_probe.dart';
import '../platform/auth_flow.dart';
import '../pre_auth_state.dart';
import '../server_entry.dart';
import '../server_manager.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.serverManager,
    required this.appName,
    this.logo,
    this.defaultBackendUrl,
    this.autoConnectUrl,
  });

  final ServerManager serverManager;
  final String appName;
  final Widget? logo;
  final String? defaultBackendUrl;
  final String? autoConnectUrl;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// -- Connection state machine --

sealed class _ConnectState {
  const _ConnectState();
}

final class _UrlInput extends _ConnectState {
  const _UrlInput({this.error});
  final String? error;
}

final class _Probing extends _ConnectState {
  const _Probing();
}

final class _Consent extends _ConnectState {
  const _Consent({required this.probeResult, required this.providers});
  final ConnectionSuccess probeResult;
  final List<AuthProviderConfig> providers;
}

final class _ProviderSelection extends _ConnectState {
  const _ProviderSelection(
      {required this.probeResult, required this.providers});
  final ConnectionSuccess probeResult;
  final List<AuthProviderConfig> providers;
}

final class _Authenticating extends _ConnectState {
  const _Authenticating();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _logoSize = 64.0;
  static const _maxCollapsedServers = 5;

  late final void Function() _unsubscribe;
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  _ConnectState _state = const _UrlInput();
  bool _showAllServers = false;
  bool _hasUrlText = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);
    _unsubscribe = widget.serverManager.servers.subscribe((_) {
      if (mounted) {
        final servers = widget.serverManager.servers.value;
        if (servers.isEmpty &&
            _urlController.text.isEmpty &&
            widget.defaultBackendUrl != null) {
          _urlController.text = widget.defaultBackendUrl!;
        }
        setState(() {});
      }
    });
    final autoConnect = widget.autoConnectUrl;
    if (autoConnect != null) {
      _urlController.text = autoConnect;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect();
      });
    } else {
      final defaultUrl = widget.defaultBackendUrl;
      if (defaultUrl != null && widget.serverManager.servers.value.isEmpty) {
        _urlController.text = defaultUrl;
      }
    }
  }

  void _onUrlChanged() {
    final hasText = _urlController.text.isNotEmpty;
    if (hasText != _hasUrlText) {
      setState(() => _hasUrlText = hasText);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _urlController.removeListener(_onUrlChanged);
    _unsubscribe();
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody(context));
  }

  bool _handleKey(KeyEvent event) {
    if (_state is! _UrlInput) return false;
    if (_urlFocusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;
    _urlFocusNode.requestFocus();
    return false;
  }

  Widget _buildBody(BuildContext context) {
    final servers = widget.serverManager.servers.value;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...switch (_state) {
                _UrlInput() => _buildUrlInput(context),
                _Probing() => _buildProbing(context),
                _Consent(:final probeResult, :final providers) =>
                  _buildConsent(context, probeResult, providers),
                _ProviderSelection(:final probeResult, :final providers) =>
                  _buildProviderSelection(context, probeResult, providers),
                _Authenticating() => _buildAuthenticating(context),
              },
              if (servers.isNotEmpty && _state is _UrlInput)
                ..._buildServerSection(context, servers),
            ],
          ),
        ),
      ),
    );
  }

  // -- Header --

  List<Widget> _buildHeader(BuildContext context, String subtitle) {
    final theme = Theme.of(context);

    return [
      if (widget.logo != null)
        SizedBox(width: _logoSize, height: _logoSize, child: widget.logo)
      else
        Icon(
          Icons.dns_outlined,
          size: _logoSize,
          color: theme.colorScheme.primary,
        ),
      const SizedBox(height: 16),
      Text(
        widget.appName,
        style: theme.textTheme.headlineMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 32),
    ];
  }

  // -- State UIs --

  List<Widget> _buildUrlInput(BuildContext context) {
    final theme = Theme.of(context);
    final error = (_state as _UrlInput).error;

    return [
      ..._buildHeader(context, 'Enter the URL of your backend server'),
      Form(
        key: _formKey,
        child: TextFormField(
          controller: _urlController,
          focusNode: _urlFocusNode,
          autofocus: true,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: _validateUrl,
          decoration: InputDecoration(
            labelText: 'Backend URL',
            hintText: 'api.example.com',
            prefixIcon: const Icon(Icons.link),
            border: const OutlineInputBorder(),
            suffixIcon: _hasUrlText
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _urlController.clear(),
                  )
                : null,
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onFieldSubmitted: (_) => _connect(),
        ),
      ),
      const SizedBox(height: 16),
      if (error != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      FilledButton.icon(
        onPressed: _connect,
        icon: const Icon(Icons.login),
        label: const Text('Connect'),
      ),
    ];
  }

  List<Widget> _buildProbing(BuildContext context) {
    return [
      ..._buildHeader(context, 'Connecting...'),
      const Center(child: CircularProgressIndicator()),
    ];
  }

  List<Widget> _buildConsent(
    BuildContext context,
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    final notice = ref.read(consentNoticeProvider)!;
    return [
      ..._buildHeader(context, 'Sign in to continue'),
      Text(notice.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      Text(notice.body),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: _resetToUrlInput,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: () => _proceedAfterConsent(
                probeResult: probeResult, providers: providers),
            child: Text(notice.acknowledgmentLabel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildProviderSelection(
    BuildContext context,
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    return [
      ..._buildHeader(context, 'Sign in to continue'),
      Text(
        'Choose authentication provider',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      for (final provider in providers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton(
            onPressed: () => _authenticate(provider, probeResult: probeResult),
            child: Text(provider.name),
          ),
        ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _resetToUrlInput,
        child: const Text('Change server'),
      ),
    ];
  }

  List<Widget> _buildAuthenticating(BuildContext context) {
    return [
      ..._buildHeader(context, 'Signing in...'),
      const Center(child: CircularProgressIndicator()),
    ];
  }

  // -- Server section --

  List<Widget> _buildServerSection(
    BuildContext context,
    Map<String, ServerEntry> servers,
  ) {
    final loggedOut = servers.values.where((e) => !e.isConnected).toList();
    final connectedCount = servers.values.where((e) => e.isConnected).length;

    final visibleServers = _showAllServers
        ? loggedOut
        : loggedOut.take(_maxCollapsedServers).toList();
    final hiddenCount = loggedOut.length - visibleServers.length;

    return [
      const SizedBox(height: 32),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Your servers',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => context.push('/servers'),
          child: Text('All servers ($connectedCount connected)'),
        ),
      ),
      for (final entry in visibleServers)
        ListTile(
          title: Text(formatServerUrl(entry.serverUrl)),
          trailing: IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => widget.serverManager.removeServer(entry.serverId),
          ),
          onTap: () {
            _urlController.text = entry.serverUrl.toString();
            _connect();
          },
        ),
      if (hiddenCount > 0)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _showAllServers = true),
            child: Text('Show $hiddenCount more'),
          ),
        ),
    ];
  }

  // -- URL validation --

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Server address is required';
    }

    if (RegExp(r'\s').hasMatch(value.trim())) {
      return "Can't contain whitespaces";
    }

    final separatorIndex = value.indexOf('://');
    if (separatorIndex == -1) return null;

    final scheme = value.substring(0, separatorIndex);
    if (!['http', 'https'].contains(scheme)) {
      return 'Only http and https are supported';
    }

    return null;
  }

  // -- Connection flow --

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _state = const _Probing());

    try {
      final input = _urlController.text.trim();
      final httpClient = ref.read(probeClientProvider);
      final discover = ref.read(discoverProvidersProvider);

      final result = await probeConnection(
        input: input,
        httpClient: httpClient,
        discover: discover,
      );

      if (!mounted) return;

      switch (result) {
        case ConnectionSuccess():
          final resultId = serverIdFromUrl(result.serverUrl);
          final existing = widget.serverManager.servers.value[resultId];
          if (existing != null && existing.isConnected) {
            context.go('/lobby');
            return;
          }
          if (result.isInsecure) {
            final accepted = await _showInsecureWarning();
            if (!mounted || !accepted) {
              _resetToUrlInput();
              return;
            }
          }
          _proceedAfterProbe(probeResult: result, providers: result.providers);
        case ConnectionFailure(:final error):
          setState(() {
            _state = _UrlInput(error: _describeConnectionError(error, input));
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = _UrlInput(error: 'Unexpected error: $e'));
      }
    }
  }

  Future<bool> _showInsecureWarning() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insecure Connection'),
        content: const Text(
          'This connection is not encrypted. Your data, including '
          'credentials, may be visible to others on the network.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand, connect anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _proceedAfterProbe({
    required ConnectionSuccess probeResult,
    required List<AuthProviderConfig> providers,
  }) {
    final notice = ref.read(consentNoticeProvider);
    if (notice != null) {
      setState(() => _state = _Consent(
            probeResult: probeResult,
            providers: providers,
          ));
    } else {
      _proceedAfterConsent(probeResult: probeResult, providers: providers);
    }
  }

  void _proceedAfterConsent({
    required ConnectionSuccess probeResult,
    required List<AuthProviderConfig> providers,
  }) {
    if (providers.isEmpty) {
      _addServerNoAuth(probeResult);
    } else if (providers.length == 1) {
      _authenticate(providers.first, probeResult: probeResult);
    } else {
      setState(() => _state = _ProviderSelection(
            probeResult: probeResult,
            providers: providers,
          ));
    }
  }

  void _addServerNoAuth(ConnectionSuccess probeResult) {
    final serverId = serverIdFromUrl(probeResult.serverUrl);
    widget.serverManager.addServer(
      serverId: serverId,
      serverUrl: probeResult.serverUrl,
      requiresAuth: false,
    );
    DefaultBackendUrlStorage.save(probeResult.serverUrl.toString());
    if (mounted) context.go('/lobby');
  }

  Future<void> _authenticate(
    AuthProviderConfig provider, {
    required ConnectionSuccess probeResult,
  }) async {
    setState(() => _state = const _Authenticating());

    final authFlow = ref.read(authFlowProvider);

    final discoveryUrl =
        '${provider.serverUrl}/.well-known/openid-configuration';

    await PreAuthStateStorage.save(PreAuthState(
      serverUrl: probeResult.serverUrl,
      providerId: provider.id,
      discoveryUrl: discoveryUrl,
      clientId: provider.clientId,
      createdAt: DateTime.timestamp(),
    ));

    try {
      final authResult = await authFlow.authenticate(
        provider,
        backendUrl: probeResult.serverUrl,
      );

      if (!mounted) return;

      final serverId = serverIdFromUrl(probeResult.serverUrl);
      final entry = widget.serverManager.addServer(
        serverId: serverId,
        serverUrl: probeResult.serverUrl,
      );

      entry.auth.login(
        provider: OidcProvider(
          discoveryUrl: discoveryUrl,
          clientId: provider.clientId,
        ),
        tokens: AuthTokens(
          accessToken: authResult.accessToken,
          refreshToken: authResult.refreshToken ?? '',
          expiresAt: authResult.expiresAt ??
              DateTime.now().add(const Duration(hours: 1)),
          idToken: authResult.idToken,
        ),
      );

      await PreAuthStateStorage.clear();
      DefaultBackendUrlStorage.save(probeResult.serverUrl.toString());
      if (mounted) context.go('/lobby');
    } on AuthRedirectInitiated {
      // Web: browser is redirecting to IdP.
    } on AuthException catch (e) {
      await PreAuthStateStorage.clear();
      if (!mounted) return;
      setState(() => _state = _UrlInput(error: e.message));
    }
  }

  void _resetToUrlInput() {
    setState(() => _state = const _UrlInput());
  }

  String _describeConnectionError(Object error, String url) {
    final String detail;
    final String? serverDetail;
    switch (error) {
      case agent.AuthException(:final statusCode, :final serverMessage):
        serverDetail = serverMessage;
        detail = statusCode == 401
            ? 'Authentication required. $url requires login '
                'credentials. ($statusCode)'
            : 'Access denied by $url. The server may require additional '
                'configuration or may be blocking this connection. '
                '($statusCode)';
      case NotFoundException(:final serverMessage):
        serverDetail = serverMessage;
        detail = 'Server at $url was reached, but the expected API '
            'endpoint was not found. The server version may be '
            'incompatible. (404)';
      case CancelledException(:final reason):
        serverDetail = null;
        detail = reason != null
            ? 'Request cancelled: $reason'
            : 'Request cancelled.';
      case NetworkException(:final isTimeout, :final message):
        serverDetail = isTimeout ? null : message;
        detail = isTimeout
            ? 'Connection to $url timed out. '
                'The server may be slow or unreachable.'
            : 'Cannot reach $url. Check the URL and your '
                'network connection.';
      case ApiException(:final statusCode, :final serverMessage):
        serverDetail = serverMessage;
        detail = statusCode >= 500
            ? 'Server error at $url. '
                'Please try again later. ($statusCode)'
            : 'Unexpected response from $url. ($statusCode)';
      default:
        return 'Connection to $url failed: $error';
    }
    return serverDetail != null ? '$detail\n\nDetails: $serverDetail' : detail;
  }
}
