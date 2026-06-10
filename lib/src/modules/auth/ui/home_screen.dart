import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../../../core/routes.dart';
import '../auth_providers.dart';
import '../connect_flow.dart';
import '../consent_notice.dart';
import '../connection_probe.dart';
import '../server_entry.dart';
import '../server_manager.dart';
import 'connect_flow_rail.dart';
import 'home_shell.dart';
import 'package:soliplex_design/soliplex_design.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.serverManager,
    required this.appName,
    this.logo,
    this.defaultBackendUrl,
    this.autoConnectUrl,
    this.autoConnectReturnTo,
  });

  final ServerManager serverManager;
  final String appName;
  final Widget? logo;
  final String? defaultBackendUrl;
  final String? autoConnectUrl;

  /// In-app route to return the user to after a successful re-auth
  /// triggered by this auto-connect. Forwarded to
  /// [ConnectFlow.connect] which stashes it in `PreAuthState` for the
  /// callback to honor.
  final String? autoConnectReturnTo;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
      inactivityLogoutFlags: ref.read(inactivityLogoutFlagsProvider),
      consentNotice: ref.read(consentNoticeProvider),
    );

    _urlController.addListener(_onUrlChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);

    _unsubscribeFlow = _flow.state.subscribe((state) {
      if (state is Connected && mounted) {
        context.go(AppRoutes.lobby);
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
    _unsubscribeFlow();
    _unsubscribeServers();
    _flow.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _urlController.removeListener(_onUrlChanged);
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.value;
    final state = _flow.state.value;
    final showRail =
        MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.desktop;

    return HomeShell(
      appName: widget.appName,
      logo: widget.logo,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showRail) ...[
            ConnectFlowRail(current: stepForConnectState(state)),
            const SizedBox(height: SoliplexSpacing.s6),
          ],
          ...switch (state) {
            UrlInput() => _buildUrlInput(context),
            Probing() => _buildProbing(context),
            InsecureWarning(:final probeResult) =>
              _buildInsecureWarning(context, probeResult),
            Consent(:final notice, :final probeResult, :final providers) =>
              _buildConsent(context, notice, probeResult, providers),
            ProviderSelection(:final providers) =>
              _buildProviderSelection(context, providers),
            Authenticating() => _buildAuthenticating(context),
            Connected() => _buildAuthenticating(context),
          },
          if (servers.isNotEmpty && state is UrlInput)
            ..._buildServerSection(context, servers),
        ],
      ),
    );
  }

  bool _handleKey(KeyEvent event) {
    if (_flow.state.value is! UrlInput) return false;
    if (_urlFocusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;
    _urlFocusNode.requestFocus();
    return false;
  }

  // -- Per-state heading --

  /// A single centered heading for a flow state. The persistent [HomeShell]
  /// top bar now carries the brand mark and name, so each state only needs to
  /// name itself. PR2 reshapes these into title + description blocks.
  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
    );
  }

  // -- State UIs --

  List<Widget> _buildUrlInput(BuildContext context) {
    final message = (_flow.state.value as UrlInput).message;

    return [
      _heading(context, 'Connect to a Soliplex server'),
      Form(
        key: _formKey,
        child: SoliplexInput(
          controller: _urlController,
          focusNode: _urlFocusNode,
          autofocus: true,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: _validateUrl,
          label: 'Backend URL',
          hintText: 'api.example.com',
          leadingIcon: const Icon(Icons.link),
          trailingIcon: _hasUrlText
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                )
              : null,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      if (message != null) ...[
        UrlMessageBanner(message: message),
        const SizedBox(height: SoliplexSpacing.s4),
      ],
      SoliplexButton.filled(
        onPressed: _connect,
        icon: const Icon(Icons.login),
        child: const Text('Connect'),
      ),
    ];
  }

  List<Widget> _buildProbing(BuildContext context) {
    return [
      _heading(context, 'Probing server…'),
      const Center(child: CircularProgressIndicator()),
    ];
  }

  List<Widget> _buildInsecureWarning(
    BuildContext context,
    ConnectionSuccess probeResult,
  ) {
    final theme = Theme.of(context);

    return [
      _heading(context, 'Insecure connection'),
      Icon(Icons.warning_amber, size: 48, color: theme.colorScheme.warning),
      const SizedBox(height: SoliplexSpacing.s4),
      Text(
        'This connection to ${formatServerUrl(probeResult.serverUrl)} is not '
        'encrypted. Your data, including credentials, may be visible to '
        'others on the network.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: SoliplexSpacing.s6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SoliplexButton.outlined(
            onPressed: _flow.reset,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: SoliplexSpacing.s4),
          SoliplexButton.filled(
            onPressed: _flow.acceptInsecure,
            child: const Text('Connect anyway'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildConsent(
    BuildContext context,
    ConsentNotice notice,
    ConnectionSuccess probeResult,
    List<AuthProviderConfig> providers,
  ) {
    return [
      _heading(context, 'Before you connect'),
      Text(notice.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: SoliplexSpacing.s4),
      Text(notice.body, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: SoliplexSpacing.s4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SoliplexButton.outlined(
            onPressed: _flow.reset,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: SoliplexSpacing.s4),
          SoliplexButton.filled(
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
      _heading(context, 'Sign in to continue'),
      Text(
        'Choose authentication provider',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      for (final provider in providers)
        Padding(
          padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
          child: SoliplexButton.filled(
            onPressed: () => _flow.selectProvider(provider),
            child: Text(provider.name),
          ),
        ),
      const SizedBox(height: SoliplexSpacing.s2),
      SoliplexButton.text(
        onPressed: _flow.reset,
        child: const Text('Change server'),
      ),
    ];
  }

  List<Widget> _buildAuthenticating(BuildContext context) {
    return [
      _heading(context, 'Finish signing in'),
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
      const SizedBox(height: SoliplexSpacing.s6),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s3),
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
      if (connectedCount > 0)
        Align(
          alignment: Alignment.centerRight,
          child: SoliplexButton.text(
            onPressed: () => context.go(AppRoutes.lobby),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward),
            child: const Text('Go to Lobby'),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: SoliplexButton.text(
          onPressed: () => context.push(AppRoutes.servers),
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
          child: SoliplexButton.text(
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
    _flow.connect(
      _urlController.text.trim(),
      returnTo: widget.autoConnectReturnTo,
    );
  }
}

/// Renders a [ConnectMessage] on the URL-input screen.
///
/// [ConnectError] renders a red error banner with an icon.
/// [ConnectNotice] renders a quiet neutral message with no container.
class UrlMessageBanner extends StatelessWidget {
  const UrlMessageBanner({super.key, required this.message});

  final ConnectMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (message) {
      ConnectError(:final text) => Container(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(soliplexRadii.sm),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ConnectNotice(:final text) => Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    };
  }
}
