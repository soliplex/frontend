import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.copy_button');

class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.tooltip = 'Copy',
    this.iconSize = 20,
    this.icon = Icons.copy,
  });

  final String text;
  final String tooltip;
  final double iconSize;
  final IconData icon;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

enum _CopyFeedback { idle, success, error }

class _CopyButtonState extends State<CopyButton> {
  _CopyFeedback _feedback = _CopyFeedback.idle;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } on Exception catch (e, st) {
      _logger.warning('Clipboard.setData failed', error: e, stackTrace: st);
      _showFeedback(_CopyFeedback.error);
      return;
    }
    _showFeedback(_CopyFeedback.success);
  }

  void _showFeedback(_CopyFeedback value) {
    if (!mounted) return;
    setState(() => _feedback = value);
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = _CopyFeedback.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (_feedback) {
      _CopyFeedback.idle => (widget.icon, theme.colorScheme.onSurfaceVariant),
      _CopyFeedback.success => (
          Icons.check,
          theme.colorScheme.onSurfaceVariant
        ),
      _CopyFeedback.error => (Icons.error_outline, theme.colorScheme.error),
    };
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: _feedback == _CopyFeedback.idle ? _copy : null,
          borderRadius: BorderRadius.circular(context.radii.sm),
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s1),
            child: Icon(icon, size: widget.iconSize, color: color),
          ),
        ),
      ),
    );
  }
}
