import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../auth_providers.dart';
import '../connect_flow.dart';
import '../connection_probe.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _logoSize = 64.0;
  static const _maxCollapsedServers = 5;

  late final ConnectFlow _flow;
  late final void Function() _unsubscribeFlow;
  late final void Function() _unsubscribeServers;
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _showAllServers = false;
  bool _hasUrlText = false;

  @override
  void initState() {
    super.initState();

    _flow = ConnectFlow(
      serverManager: widget.serverManager,
      probeClient: ref.read(probeClientProvider),
      discover: ref.read(discoverProvidersProvider),
      authFlow: ref.read(authFlowProvider),
      consentNotice: ref.read(consentNoticeProvider),
    );

    _urlController.addListener(_onUrlChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);

    _unsubscribeFlow = _flow.state.subscribe((state) {
      if (state is Connected && mounted) {
        context.go('/lobby');
        return;
      }
      if (mounted) setState(() {});
    });

    _unsubscribeServers = widget.serverManager.servers.subscribe((_) {
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
    _flow.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _urlController.removeListener(_onUrlChanged);
    _unsubscribeFlow();
    _unsubscribeServers();
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody(context));
  }

  bool _handleKey(KeyEvent event) {
    if (_flow.state.value is! UrlInput) return false;
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
              ...switch (_flow.state.value) {
                UrlInput() => _buildUrlInput(context),
                Probing() => _buildProbing(context),
                InsecureWarning(:final probeResult) =>
                  _buildInsecureWarning(context, probeResult),
                Consent(:final probeResult, :final providers) =>
                  _buildConsent(context, probeResult, providers),
                ProviderSelection(:final providers) =>
                  _buildProviderSelection(context, providers),
                Authenticating() => _buildAuthenticating(context),
                Connected() => _buildAuthenticating(context),
              },
              if (servers.isNotEmpty && _flow.state.value is UrlInput)
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
    final error = (_flow.state.value as UrlInput).error;

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

  List<Widget> _buildInsecureWarning(
    BuildContext context,
    ConnectionSuccess probeResult,
  ) {
    final theme = Theme.of(context);

    return [
      ..._buildHeader(context, 'Insecure Connection'),
      Icon(Icons.warning_amber, size: 48, color: theme.colorScheme.error),
      const SizedBox(height: 16),
      Text(
        'This connection to ${formatServerUrl(probeResult.serverUrl)} is not '
        'encrypted. Your data, including credentials, may be visible to '
        'others on the network.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: _flow.reset,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: _flow.acceptInsecure,
            child: const Text('Connect anyway'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildConsent(
    BuildContext context,
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    final notice = _flow.consentNotice!;
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
            onPressed: _flow.reset,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: _flow.acknowledgeConsent,
            child: Text(notice.acknowledgmentLabel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildProviderSelection(
    BuildContext context,
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
            onPressed: () => _flow.selectProvider(provider),
            child: Text(provider.name),
          ),
        ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _flow.reset,
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

  // -- Actions --

  void _connect() {
    if (!_formKey.currentState!.validate()) return;
    _flow.connect(_urlController.text.trim());
  }
}
