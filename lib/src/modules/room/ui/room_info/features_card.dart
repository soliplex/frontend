import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import '../../../../../soliplex_frontend.dart';
import 'room_info_widgets.dart';

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
          value: room.enableAttachments ? 'Enabled' : 'Disabled',
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
    } on PlatformException catch (e, st) {
      debugPrint('Clipboard.setData PlatformException: $e\n$st');
      _showCopyFeedback(_TokenCopyState.error);
      return;
    } on Exception catch (e, st) {
      debugPrint('Clipboard.setData failed: $e\n$st');
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
              height: SoliplexSpacing.s5,
              width: SoliplexSpacing.s5,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry token'),
              onPressed: () => setState(() {
                _tokenFuture = widget.api.getMcpToken(widget.roomId);
              }),
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
          child: OutlinedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label),
            onPressed: _copyState == _TokenCopyState.idle
                ? () => _copyToken(token)
                : null,
          ),
        );
      },
    );
  }
}
