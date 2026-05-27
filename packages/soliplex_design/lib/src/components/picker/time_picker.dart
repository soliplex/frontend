import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/button/loading_indicator.dart';

/// Imperative wrapper around Material's [showTimePicker]. The picker
/// inherits Soliplex theming via [Theme.of], so this is mostly a
/// shorter-argument-list facade.
Future<TimeOfDay?> showSoliplexTimePicker({
  required BuildContext context,
  TimeOfDay? initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime ?? TimeOfDay.now(),
    helpText: helpText,
  );
}

/// Inline time-picker form field. Renders the selected time as
/// read-only text with a trailing clock icon; tap opens
/// [showSoliplexTimePicker].
///
/// Mirrors `SoliplexDatePickerField` for parity — same axes, same
/// behavior.
class SoliplexTimePickerField extends StatefulWidget {
  const SoliplexTimePickerField({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.isLoading = false,
  });

  final TimeOfDay? initialValue;
  final ValueChanged<TimeOfDay?>? onChanged;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool isLoading;

  @override
  State<SoliplexTimePickerField> createState() =>
      _SoliplexTimePickerFieldState();
}

class _SoliplexTimePickerFieldState extends State<SoliplexTimePickerField> {
  TimeOfDay? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final isInteractive = widget.enabled && !widget.isLoading;
    final controller = TextEditingController(
      text: _value == null ? '' : localizations.formatTimeOfDay(_value!),
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: isInteractive,
      onTap: () async {
        final picked = await showSoliplexTimePicker(
          context: context,
          initialTime: _value,
        );
        if (picked == null) return;
        setState(() => _value = picked);
        widget.onChanged?.call(picked);
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: widget.isLoading
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ButtonLoadingIndicator(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
              )
            : const Icon(Icons.schedule_outlined),
      ),
    );
  }
}
