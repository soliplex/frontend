import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show FeedbackType;

import 'feedback_reason_dialog.dart';
import '../../../../soliplex_frontend.dart';

enum _FeedbackPhase { idle, countdown, modal, submitted }

class FeedbackButtons extends StatefulWidget {
  const FeedbackButtons({
    required this.onFeedbackSubmit,
    this.countdownSeconds = 5,
    super.key,
  });

  final void Function(FeedbackType feedback, String? reason) onFeedbackSubmit;
  final int countdownSeconds;

  @override
  State<FeedbackButtons> createState() => _FeedbackButtonsState();
}

class _FeedbackButtonsState extends State<FeedbackButtons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  _FeedbackPhase _phase = _FeedbackPhase.idle;
  FeedbackType? _direction;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.countdownSeconds),
    );
  }

  @override
  void dispose() {
    if (_phase == _FeedbackPhase.countdown || _phase == _FeedbackPhase.modal) {
      widget.onFeedbackSubmit(_direction!, null);
    }
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTap(FeedbackType tapped) {
    switch (_phase) {
      case _FeedbackPhase.idle:
        _startCountdown(tapped);
      case _FeedbackPhase.countdown:
        if (tapped == _direction) {
          _controller.stop();
          _countdownTimer?.cancel();
          setState(() {
            _phase = _FeedbackPhase.idle;
            _direction = null;
          });
        } else {
          _startCountdown(tapped);
        }
      case _FeedbackPhase.modal:
        break;
      case _FeedbackPhase.submitted:
        if (tapped != _direction) {
          _startCountdown(tapped);
        }
    }
  }

  void _startCountdown(FeedbackType direction) {
    _countdownTimer?.cancel();
    setState(() {
      _phase = _FeedbackPhase.countdown;
      _direction = direction;
    });
    _controller.reverse(from: 1);
    _countdownTimer = Timer(
      Duration(seconds: widget.countdownSeconds),
      () {
        if (mounted && _phase == _FeedbackPhase.countdown) {
          _submit(null);
        }
      },
    );
  }

  Future<void> _onTellUsWhyTap() async {
    _countdownTimer?.cancel();
    _controller.stop();
    setState(() => _phase = _FeedbackPhase.modal);

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const FeedbackReasonDialog(),
    );

    if (!mounted) return;

    if (reason != null) {
      _submit(reason.trim().isEmpty ? null : reason.trim());
    } else {
      _startCountdown(_direction!);
    }
  }

  void _submit(String? reason) {
    final direction = _direction!;
    setState(() => _phase = _FeedbackPhase.submitted);
    widget.onFeedbackSubmit(direction, reason);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUpActive =
        _direction == FeedbackType.thumbsUp && _phase != _FeedbackPhase.idle;
    final isDownActive =
        _direction == FeedbackType.thumbsDown && _phase != _FeedbackPhase.idle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThumbButton(
          tooltip: 'Thumbs up',
          icon: isUpActive ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
          color: isUpActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          onTap: () => _onTap(FeedbackType.thumbsUp),
        ),
        const SizedBox(width: SoliplexSpacing.s1),
        _ThumbButton(
          tooltip: 'Thumbs down',
          icon: isDownActive ? Icons.thumb_down : Icons.thumb_down_alt_outlined,
          color: isDownActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          onTap: () => _onTap(FeedbackType.thumbsDown),
        ),
        if (_phase == _FeedbackPhase.countdown) ...[
          const SizedBox(width: SoliplexSpacing.s1),
          _CountdownIndicator(
            controller: _controller,
            totalSeconds: widget.countdownSeconds,
          ),
          const SizedBox(width: SoliplexSpacing.s1),
          InkWell(
            onTap: _onTellUsWhyTap,
            borderRadius: BorderRadius.circular(4),
            child: Text(
              'Tell us why!',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThumbButton extends StatelessWidget {
  const _ThumbButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _CountdownIndicator extends StatelessWidget {
  const _CountdownIndicator({
    required this.controller,
    required this.totalSeconds,
  });

  final AnimationController controller;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: SoliplexSpacing.s6,
      height: SoliplexSpacing.s6,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final remaining = (totalSeconds * controller.value).ceil();
          return Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: controller.value,
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
              Text(
                '$remaining',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 8,
                  height: 1,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
