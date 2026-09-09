import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'No $label in this room.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class DialogButton extends StatelessWidget {
  const DialogButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SoliplexButton.text(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

const jsonPrettyEncoder = JsonEncoder.withIndent('  ');

/// Formats a dynamic value for display, using pretty-printed JSON for
/// complex values (maps/lists) and plain text for scalars.
SelectableText formatDynamicValue(
  BuildContext context,
  Object? value, {
  TextStyle? style,
}) {
  final isComplex = value is Map || value is Iterable;
  String text;
  if (isComplex) {
    try {
      text = jsonPrettyEncoder.convert(value);
    } catch (_) {
      text = value.toString();
    }
  } else {
    text = '$value';
  }
  return SelectableText(
    text,
    style: isComplex ? context.monospaceOn(style) : style,
  );
}

/// Dialog rendering one or more raw parameter maps the backend passes
/// through verbatim, each under its own heading.
class RawParametersDialog extends StatelessWidget {
  const RawParametersDialog({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;

  /// Section heading paired with the map to render beneath it. An empty map
  /// renders as "Empty" rather than being omitted, so a section the backend
  /// sent nothing for still accounts for itself.
  final List<(String, Map<String, dynamic>)> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sectionStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    final noneStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    Widget mapSection(String heading, Map<String, dynamic> data) {
      final isEmpty = data.isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: sectionStyle),
          const SizedBox(height: SoliplexSpacing.s2),
          if (isEmpty)
            Text('Empty', style: noneStyle)
          else
            for (final entry in data.entries) ...[
              SizedBox(
                width: double.infinity,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(SoliplexSpacing.s3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key, style: labelStyle),
                        const SizedBox(height: SoliplexSpacing.s1),
                        formatDynamicValue(
                          context,
                          entry.value,
                          style: valueStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s2),
            ],
        ],
      );
    }

    return AlertDialog(
      title: Text(title, overflow: TextOverflow.ellipsis, maxLines: 1),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (heading, data) in sections) ...[
                mapSection(heading, data),
                const SizedBox(height: SoliplexSpacing.s4),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SoliplexButton.text(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
