import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show SoliplexHttpClient;
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/status_message_config.dart';
import '../status_message.dart';
import '../status_message_controller.dart';
import '../status_message_dismissals.dart';
import '../status_message_display.dart';
import '../status_message_fetcher.dart';
import '../status_message_window_format.dart';

/// Callers that can change target server while staying mounted (the lobby's
/// selected server) MUST pass `key: ValueKey(baseUrl)` so Flutter recreates
/// the state — and thus the controller — when the URL changes. The mounts
/// below do this.
class StatusMessageBanner extends ConsumerStatefulWidget {
  const StatusMessageBanner({
    required Uri baseUrl,
    required SoliplexHttpClient client,
    String? serverLabel,
    Key? key,
  }) : this._(
          baseUrl: baseUrl,
          client: client,
          serverLabel: serverLabel,
          key: key,
        );

  const StatusMessageBanner.withFetcher({
    required StatusMessageFetcher fetcher,
    String? serverLabel,
    Key? key,
  }) : this._(fetcher: fetcher, serverLabel: serverLabel, key: key);

  const StatusMessageBanner._({
    this.baseUrl,
    this.client,
    this.fetcher,
    this.serverLabel,
    super.key,
  });

  final Uri? baseUrl;
  final SoliplexHttpClient? client;
  final StatusMessageFetcher? fetcher;

  /// Which server this message is about, shown in the expanded view for
  /// disambiguation. The mounts pass `ServerEntry.displayName` (the server's
  /// name, or a cleaned host label when unnamed). Null → no label.
  final String? serverLabel;

  @override
  ConsumerState<StatusMessageBanner> createState() =>
      _StatusMessageBannerState();
}

class _StatusMessageBannerState extends ConsumerState<StatusMessageBanner> {
  late final StatusMessageController _controller;
  Timer? _ticker;
  bool _expanded = false;
  StatusMessageDismissals? _dismissals;

  /// Reads the shell-provided config. The banner is self-contained and may be
  /// dropped into any tree; outside a shell (e.g. a widget test that doesn't
  /// install the shell scope) there is no provider, so the banner stays inert.
  StatusMessageConfig _readConfig() {
    try {
      return ref.read(statusMessageConfigProvider);
    } on StateError {
      return StatusMessageConfig.disabled;
    }
  }

  /// Reads the session dismiss store. Guarded like the config: outside a shell
  /// there is no provider, so treat it as "nothing dismissed".
  StatusMessageDismissals? _readDismissals() {
    try {
      return ref.read(statusMessageDismissalsProvider);
    } on StateError {
      return null;
    }
  }

  String get _serverKey => widget.baseUrl?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final config = _readConfig();
    final fetcher = widget.fetcher ??
        serverStatusMessageFetcher(
          baseUrl: widget.baseUrl!,
          client: widget.client!,
          path: config.filePath,
        );
    _controller = StatusMessageController(fetcher: fetcher, config: config)
      ..start();
    _dismissals = _readDismissals();
    if (config.isEnabled) {
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final message = _controller.message.value;
      if (message == null) return const SizedBox.shrink();
      if (_dismissals?.isDismissed(_serverKey, message.id) ?? false) {
        return const SizedBox.shrink();
      }
      final display = resolveVisibility(message, now: DateTime.now());
      if (display is MessageHidden) return const SizedBox.shrink();
      return _buildBanner(context, message, display);
    });
  }

  (Color, Color) _colors(BuildContext context, MessageIntent intent) {
    final colors = SoliplexTheme.of(context).colors;
    return switch (intent) {
      MessageIntent.warning => (
          colors.warningContainer,
          colors.onWarningContainer
        ),
      MessageIntent.info => (colors.infoContainer, colors.onInfoContainer),
    };
  }

  IconData _icon(MessageCategory category) => switch (category) {
        MessageCategory.maintenance => Icons.build,
        MessageCategory.general => Icons.campaign,
      };

  Widget? _pill(
      BuildContext context, StatusMessage message, MessageDisplay display) {
    final text = switch (display) {
      MessageUpcoming(:final remaining) =>
        'STARTS IN ${formatCountdown(remaining)}',
      MessageActive(:final remaining) =>
        'ENDS IN ${formatCountdown(remaining)}',
      _ => null,
    };
    if (text == null) return null;
    final intent = message.intent == MessageIntent.warning
        ? BadgeIntent.warning
        : BadgeIntent.info;
    return SoliplexBadge(
      intent: intent,
      icon: const Icon(Icons.schedule),
      label: Text(
        text,
        style: context.monospaceOn(Theme.of(context).textTheme.labelSmall),
      ),
    );
  }

  Widget _buildBanner(
      BuildContext context, StatusMessage message, MessageDisplay display) {
    final (bg, fg) = _colors(context, message.intent);
    final pill = _pill(context, message, display);
    final window = message.window;
    return Container(
      color: bg,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(SoliplexSpacing.s2),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: Icon(_icon(message.category), color: fg),
              ),
              const SizedBox(width: SoliplexSpacing.s3),
              Expanded(
                child: _expanded
                    ? _expandedContent(context, message, pill, window, fg)
                    : _collapsedContent(context, message, pill, fg),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: fg,
                tooltip: 'Dismiss',
                onPressed: () {
                  _dismissals?.markDismissed(_serverKey, message.id);
                  setState(() {});
                },
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SoliplexButton.text(
              isCompact: true,
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Show less' : 'Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedContent(
      BuildContext context, StatusMessage message, Widget? pill, Color fg) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                message.title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: fg),
              ),
            ),
            if (pill != null) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              pill,
            ],
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        Text(
          message.body,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: fg),
        ),
      ],
    );
  }

  Widget _expandedContent(BuildContext context, StatusMessage message,
      Widget? pill, MessageWindow? window, Color fg) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.title,
          style: theme.textTheme.titleSmall?.copyWith(color: fg),
        ),
        if (widget.serverLabel case final label? when label.isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
        if (pill != null) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Align(alignment: Alignment.centerLeft, child: pill),
        ],
        if (window != null) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          LayoutBuilder(
            builder: (context, constraints) => Text(
              formatWindowRange(
                window.start,
                window.end,
                stacked: constraints.maxWidth < SoliplexBreakpoints.tablet,
              ),
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
          ),
        ],
        const SizedBox(height: SoliplexSpacing.s2),
        Text(
          message.body,
          style: theme.textTheme.bodyMedium?.copyWith(color: fg),
        ),
      ],
    );
  }
}
