import 'package:flutter/material.dart';

import '../../../../soliplex_frontend.dart';
import '../../../design/color/color_scheme_extensions.dart';
import '../models/format_utils.dart';
import '../models/http_event_group.dart';

class HttpStatusDisplay extends StatelessWidget {
  const HttpStatusDisplay({
    required this.group,
    this.isSelected = false,
    super.key,
  });

  static const double _spinnerSize = 12;
  static const double _spinnerStroke = 2;

  final HttpEventGroup group;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = isSelected
        ? colorScheme.onPrimaryContainer
        : _colorForStatus(group.status, colorScheme);
    final statusText = _buildStatusText();

    final child = group.hasSpinner
        ? _buildSpinnerStatus(statusText, color, theme)
        : _buildTextStatus(statusText, color, theme);

    return Semantics(
      label: group.statusDescription,
      child: ExcludeSemantics(child: child),
    );
  }

  Color _colorForStatus(HttpEventStatus status, ColorScheme colorScheme) {
    return switch (status) {
      HttpEventStatus.pending => colorScheme.onSurfaceVariant,
      HttpEventStatus.success => colorScheme.success,
      HttpEventStatus.clientError => colorScheme.warning,
      HttpEventStatus.serverError => colorScheme.error,
      HttpEventStatus.networkError => colorScheme.error,
      HttpEventStatus.streaming => colorScheme.secondary,
      HttpEventStatus.streamComplete => colorScheme.success,
      HttpEventStatus.streamError => colorScheme.error,
    };
  }

  String _buildStatusText() {
    final response = group.response;
    final error = group.error;
    final streamEnd = group.streamEnd;
    return switch (group.status) {
      HttpEventStatus.pending => 'pending...',
      HttpEventStatus.success => '${response?.statusCode ?? '—'} OK '
          '(${response?.duration.toHttpDurationString() ?? '—'}, '
          '${response?.bodySize.toHttpBytesString() ?? '—'})',
      HttpEventStatus.clientError => '${response?.statusCode ?? '—'} '
          '(${response?.duration.toHttpDurationString() ?? '—'})',
      HttpEventStatus.serverError => '${response?.statusCode ?? '—'} '
          '(${response?.duration.toHttpDurationString() ?? '—'})',
      HttpEventStatus.networkError =>
        '${error?.exception.runtimeType ?? 'NetworkError'} '
            '(${error?.duration.toHttpDurationString() ?? '—'})',
      HttpEventStatus.streaming => streamEnd != null
          ? 'streaming... '
              '(${streamEnd.bytesReceived.toHttpBytesString()})'
          : 'streaming...',
      HttpEventStatus.streamComplete =>
        'complete (${streamEnd?.duration.toHttpDurationString() ?? '—'}, '
            '${streamEnd?.bytesReceived.toHttpBytesString() ?? '—'})',
      HttpEventStatus.streamError =>
        'error (${streamEnd?.duration.toHttpDurationString() ?? '—'})',
    };
  }

  Widget _buildTextStatus(String text, Color color, ThemeData theme) {
    return Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color));
  }

  Widget _buildSpinnerStatus(String text, Color color, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _spinnerSize,
          height: _spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: _spinnerStroke,
            color: color,
          ),
        ),
        const SizedBox(width: SoliplexSpacing.s2),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: color,
          ),
        ),
      ],
    );
  }
}
