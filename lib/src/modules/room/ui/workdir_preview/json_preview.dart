import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'code_preview.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.json_preview');

/// Pretty-prints JSON before handing it to [CodePreview]. When the
/// payload doesn't parse, renders the raw text under an inline banner
/// so the user knows the file is broken rather than wondering why it's
/// unformatted.
class JsonPreview extends StatelessWidget {
  const JsonPreview({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final pretty = tryPrettyPrintJson(content);
    if (pretty != null) {
      return CodePreview(content: pretty, language: 'json');
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s3,
            vertical: SoliplexSpacing.s2,
          ),
          color: theme.colorScheme.errorContainer,
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text(
                  "This file isn't valid JSON; showing raw contents.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: CodePreview(content: content, language: 'json')),
      ],
    );
  }
}

/// Pretty-prints [raw] as JSON with 2-space indent. Returns `null` when
/// [raw] isn't valid JSON — the parse failure is logged at warning so
/// it shows in dev/ops trails.
@visibleForTesting
String? tryPrettyPrintJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException catch (error) {
    _logger.warning(
      'json file is not valid json; rendering raw',
      attributes: {'parseError': error.message},
    );
    return null;
  }
}
