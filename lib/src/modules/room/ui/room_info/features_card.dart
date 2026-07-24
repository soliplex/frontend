import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'room_info_widgets.dart';
import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.features_card');

class FeaturesCard extends StatelessWidget {
  const FeaturesCard({
    super.key,
    required this.room,
    required this.api,
    required this.roomId,
  });

  final Room room;
  final SoliplexApi api;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'FEATURES',
      children: [
        InfoRow(
          label: 'Attachments',
          value: room.supportsAttachments ? 'Enabled' : 'Disabled',
        ),
        InfoRow(
          label: 'Allow MCP',
          value: room.allowMcp ? 'Yes' : 'No',
        ),
        if (room.allowMcp) McpTokenRow(api: api, roomId: roomId),
        if (room.aguiFeatureNames.isNotEmpty)
          InfoRow(
            label: 'AG-UI Features',
            value: room.aguiFeatureNames.join(', '),
          ),
      ],
    );
  }
}

class McpTokenRow extends StatefulWidget {
  const McpTokenRow({super.key, required this.api, required this.roomId});
  final SoliplexApi api;
  final String roomId;

  @override
  State<McpTokenRow> createState() => _McpTokenRowState();
}

enum _TokenCopyState { idle, success, error }

class _McpTokenRowState extends State<McpTokenRow> {
  Future<String>? _tokenFuture;
  _TokenCopyState _copyState = _TokenCopyState.idle;
  Timer? _copyResetTimer;

  @override
  void initState() {
    super.initState();
    _tokenFuture = widget.api.getMcpToken(widget.roomId);
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyToken(String token) async {
    try {
      await Clipboard.setData(ClipboardData(text: token));
    } on Exception catch (e, st) {
      _logger.warning('Clipboard.setData failed', error: e, stackTrace: st);
      _showCopyFeedback(_TokenCopyState.error);
      return;
    }
    _showCopyFeedback(_TokenCopyState.success);
  }

  void _showCopyFeedback(_TokenCopyState value) {
    if (!mounted) return;
    setState(() => _copyState = value);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copyState = _TokenCopyState.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: SoliplexButton.outlined(
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: () => setState(() {
                _tokenFuture = widget.api.getMcpToken(widget.roomId);
              }),
              child: const Text('Retry token'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final token = snapshot.data!;
        final (icon, label) = switch (_copyState) {
          _TokenCopyState.idle => (Icons.copy, 'Copy Token'),
          _TokenCopyState.success => (Icons.check, 'Copied'),
          _TokenCopyState.error => (Icons.error_outline, 'Copy failed'),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
          child: SoliplexButton.outlined(
            icon: Icon(icon, size: 16),
            onPressed: _copyState == _TokenCopyState.idle
                ? () => _copyToken(token)
                : null,
            child: Text(label),
          ),
        );
      },
    );
  }
}
