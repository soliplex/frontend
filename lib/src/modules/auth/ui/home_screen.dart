import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import '../../../core/routes.dart';
import '../../../shared/markdown/prose_markdown.dart';
import '../../../status_message/status_message_dismissals.dart';
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

  /// Whether the user has ticked the agreement box on the consent screen.
  /// Gates the "continue" action; reset whenever the flow leaves [Consent].
  bool _consentAgreed = false;

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
      // A fresh connection re-surfaces a maintenance banner the user dismissed
      // earlier in the session for this server.
      onServerConnected: (url) => ref
          .read(statusMessageDismissalsProvider)
          .clear(serverKey: url.toString()),
    );

    _urlController.addListener(_onUrlChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);

    _unsubscribeFlow = _flow.state.subscribe((state) {
      if (state is Connected && mounted) {
        context.go(AppRoutes.lobby);
        return;
      }
      // Drop the agreement tick on the way out of consent so a later visit
      // starts unchecked.
      if (state is! Consent) _consentAgreed = false;
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
            ProviderSelection(:final probeResult, :final providers) =>
              _buildProviderSelection(context, probeResult, providers),
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

  // -- Shared layout --

  /// Left-aligned title with an optional supporting line — the lede for each
  /// flow state. The persistent [HomeShell] top bar carries the brand mark and
  /// name, so each state just introduces itself.
  Widget _titleBlock(BuildContext context, String title,
      [String? description]) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (description != null) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // -- State UIs --

  List<Widget> _buildUrlInput(BuildContext context) {
    final message = (_flow.state.value as UrlInput).message;

    return [
      _titleBlock(
        context,
        'Connect to a Soliplex server',
        "Enter the URL of the backend you want to connect to. If you're "
            "self-hosting, that's usually a localhost address or your own "
            'domain.',
      ),
      const SizedBox(height: SoliplexSpacing.s6),
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
          helperText: 'Include http:// or https://, or just the host.',
          leadingIcon: const Icon(Icons.public),
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
        icon: const Icon(Icons.arrow_forward),
        iconAlignment: IconAlignment.end,
        child: const Text('Connect'),
      ),
    ];
  }

  List<Widget> _buildProbing(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return [
      _titleBlock(
        context,
        'Probing server…',
        'Discovering the sign-in options at the URL you entered.',
      ),
      const SizedBox(height: SoliplexSpacing.s6),
      // The probe is a single discovery call — no fake DNS / TLS sub-steps.
      _FlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Text(
                    _urlController.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.monospaceOn(theme.textTheme.bodySmall),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: SoliplexSpacing.s3),
                Text('Discovering providers…',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      SoliplexButton.outlined(
        onPressed: _flow.reset,
        child: const Text('Cancel'),
      ),
    ];
  }

  List<Widget> _buildInsecureWarning(
    BuildContext context,
    ConnectionSuccess probeResult,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return [
      _FlowCard(
        accentColor: colors.error,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s3),
                Expanded(
                  child: Text(
                    'This connection is not encrypted',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(
              "You're connecting over http://. Anyone on your network can read "
              'the traffic between you and the server, including your auth '
              'token.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SoliplexSpacing.s2),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(context.radii.sm),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                probeResult.serverUrl.toString(),
                style: context.monospaceOn(theme.textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      Row(
        children: [
          Expanded(
            child: SoliplexButton.outlined(
              onPressed: _flow.reset,
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          Expanded(
            child: SoliplexButton.filled(
              intent: ButtonIntent.danger,
              onPressed: _flow.acceptInsecure,
              child: const Text('Connect anyway'),
            ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return [
      _titleBlock(
        context,
        'Before you connect',
        'This server has a notice you need to acknowledge before signing in.',
      ),
      const SizedBox(height: SoliplexSpacing.s6),
      _FlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notice.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: SoliplexSpacing.s2),
            ProseMarkdown(
              data: notice.body,
              textStyle: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      // Pure-frontend agreement gate — the consent is the user ticking this,
      // no extra backend round-trip.
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.radii.md),
          border: Border.all(
            color: _consentAgreed ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: CheckboxListTile(
          value: _consentAgreed,
          onChanged: (v) => setState(() => _consentAgreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.md),
          ),
          title: Text(
            'I understand and agree to the usage terms.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s4),
      Row(
        children: [
          Expanded(
            child: SoliplexButton.outlined(
              onPressed: _flow.reset,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          Expanded(
            child: SoliplexButton.filled(
              onPressed: _consentAgreed ? _flow.acknowledgeConsent : null,
              child: Text(notice.acknowledgmentLabel),
            ),
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
    final info = probeResult.info;
    return [
      _titleBlock(
        context,
        'Sign in to ${info?.name ?? probeResult.serverUrl.host}',
        // Surface the server's own description when it provides one; otherwise
        // keep the generic prompt.
        info?.description ?? 'Choose how you want to authenticate.',
      ),
      const SizedBox(height: SoliplexSpacing.s6),
      for (final provider in providers) ...[
        _ProviderTile(
          provider: provider,
          onTap: () => _flow.selectProvider(provider),
        ),
        const SizedBox(height: SoliplexSpacing.s2),
      ],
      const SizedBox(height: SoliplexSpacing.s2),
      SoliplexButton.text(
        onPressed: _flow.reset,
        child: const Text('Change server'),
      ),
    ];
  }

  List<Widget> _buildAuthenticating(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return [
      Center(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s4),
            Text('Finish signing in', style: theme.textTheme.titleLarge),
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              "We've opened a secure browser window so you can sign in. Come "
              'back here once you’re done.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s6),
      SoliplexButton.outlined(
        onPressed: _flow.reset,
        child: const Text('Cancel'),
      ),
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
      for (final entry in visibleServers)
        ListTile(
          // Friendly name when known; raw address otherwise. The address
          // drops to a subtitle only when a name is shown.
          title: Text(entry.displayName),
          subtitle: entry.name != null
              ? Text(
                  formatServerUrl(entry.serverUrl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
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
            borderRadius: BorderRadius.circular(context.radii.sm),
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

/// A bordered surface card used by the connect-flow states (probing, insecure
/// warning, consent). Pass [accentColor] for a coloured left edge — used to
/// flag the insecure-connection warning.
///
/// Candidate for promotion to `soliplex_design` if other modules grow the same
/// pattern; kept local while it's auth-only.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.child, this.accentColor});

  final Widget child;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // A rounded border must be uniform, so the accent edge is a clipped bar
    // rather than a coloured left border side.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      // IntrinsicHeight gives the row a finite height (it lives in a vertical
      // scroll view) so the accent bar can stretch to the card's height.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accentColor != null) Container(width: 3, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s4),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable provider row on the sign-in screen: a derived initial avatar,
/// the provider name, and its id.
///
/// [AuthProviderConfig] carries no brand icon or "recommended" flag, so the
/// tile shows only what the discovery response actually provides.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.onTap});

  final AuthProviderConfig provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = provider.name.trim();
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(context.radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.radii.md),
        child: Container(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.radii.md),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(context.radii.sm),
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: SoliplexSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      provider.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context
                          .monospaceOn(theme.textTheme.labelSmall)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
