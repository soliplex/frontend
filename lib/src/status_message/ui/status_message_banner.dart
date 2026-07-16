import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show SoliplexHttpClient;
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/status_message_config.dart';
import '../status_message.dart';
import '../status_message_controller.dart';
import '../status_message_display.dart';
import '../status_message_fetcher.dart';

/// Callers that can change target server while staying mounted (the lobby's
/// selected server) MUST pass `key: ValueKey(baseUrl)` so Flutter recreates
/// the state — and thus the controller — when the URL changes. The mounts
/// below do this.
class StatusMessageBanner extends ConsumerStatefulWidget {
  const StatusMessageBanner({
    required Uri baseUrl,
    required SoliplexHttpClient client,
    Key? key,
  }) : this._(baseUrl: baseUrl, client: client, key: key);

  const StatusMessageBanner.withFetcher({
    required StatusMessageFetcher fetcher,
    Key? key,
  }) : this._(fetcher: fetcher, key: key);

  const StatusMessageBanner._({
    this.baseUrl,
    this.client,
    this.fetcher,
    super.key,
  });

  final Uri? baseUrl;
  final SoliplexHttpClient? client;
  final StatusMessageFetcher? fetcher;

  @override
  ConsumerState<StatusMessageBanner> createState() =>
      _StatusMessageBannerState();
}

class _StatusMessageBannerState extends ConsumerState<StatusMessageBanner> {
  late final StatusMessageController _controller;
  Timer? _ticker;
  bool _minimized = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(statusMessageConfigProvider);
    final fetcher = widget.fetcher ??
        serverStatusMessageFetcher(
          baseUrl: widget.baseUrl!,
          client: widget.client!,
          path: config.filePath,
        );
    _controller = StatusMessageController(fetcher: fetcher, config: config)
      ..start();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
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
      final display = resolveVisibility(message, now: DateTime.now());
      if (display is MessageHidden) return const SizedBox.shrink();
      return _minimized
          ? _buildMinimized(context, message, display)
          : _buildExpanded(context, message, display);
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
        'BEGINS IN ${formatCountdown(remaining)}',
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

  Widget _buildExpanded(
      BuildContext context, StatusMessage message, MessageDisplay display) {
    final (bg, fg) = _colors(context, message.intent);
    final theme = Theme.of(context);
    final pill = _pill(context, message, display);
    return Container(
      color: bg,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        message.title,
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
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.expand_less),
            color: fg,
            tooltip: 'Minimize',
            onPressed: () => setState(() => _minimized = true),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimized(
      BuildContext context, StatusMessage message, MessageDisplay display) {
    final (bg, fg) = _colors(context, message.intent);
    final theme = Theme.of(context);
    final pill = _pill(context, message, display);
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s1,
      ),
      child: Row(
        children: [
          Icon(_icon(message.category), color: fg, size: 18),
          const SizedBox(width: SoliplexSpacing.s2),
          Flexible(
            child: Text(
              message.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
          ),
          if (pill != null) ...[
            const SizedBox(width: SoliplexSpacing.s2),
            pill,
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.expand_more),
            color: fg,
            tooltip: 'Expand',
            onPressed: () => setState(() => _minimized = false),
          ),
        ],
      ),
    );
  }
}
