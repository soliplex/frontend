import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../soliplex_frontend.dart';

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
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        style: TextButton.styleFrom(
          textStyle: theme.textTheme.labelSmall,
          padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s4, vertical: SoliplexSpacing.s2),
        ),
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
    style: isComplex ? SoliplexTheme.mergeCode(context, style) : style,
  );
}
