import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/button/loading_indicator.dart';

/// Imperative wrapper around Material's [showDatePicker] — the date
/// picker inherits Soliplex theming automatically via [Theme.of], so
/// this is mostly a thinner-argument-list facade.
///
/// Defaults [firstDate] and [lastDate] to a ±100-year window around
/// `now()` if either is omitted, so call sites that don't care about
/// bounds don't have to spell them out.
Future<DateTime?> showSoliplexDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? now,
    firstDate: firstDate ?? DateTime(now.year - 100),
    lastDate: lastDate ?? DateTime(now.year + 100),
    helpText: helpText,
  );
}

/// Inline date-picker form field. Renders the selected date as
/// read-only text with a trailing calendar icon; tap opens
/// [showSoliplexDatePicker].
///
/// Mirrors `SoliplexInput`'s axes — `label` / `helperText` / `errorText`
/// pass through to the underlying [InputDecoration]; `isLoading`
/// disables the field and shows a spinner in the trailing slot; the
/// generic enabled flag short-circuits taps without showing a spinner.
class SoliplexDatePickerField extends StatefulWidget {
  const SoliplexDatePickerField({
    super.key,
    this.initialValue,
    this.onChanged,
    this.firstDate,
    this.lastDate,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.isLoading = false,
  });

  final DateTime? initialValue;
  final ValueChanged<DateTime?>? onChanged;

  /// Earliest date the user can pick. Defaults to 100 years before today.
  final DateTime? firstDate;

  /// Latest date the user can pick. Defaults to 100 years after today.
  final DateTime? lastDate;

  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool isLoading;

  @override
  State<SoliplexDatePickerField> createState() =>
      _SoliplexDatePickerFieldState();
}

class _SoliplexDatePickerFieldState extends State<SoliplexDatePickerField> {
  DateTime? _value;

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
      text: _value == null ? '' : localizations.formatFullDate(_value!),
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: isInteractive,
      onTap: () async {
        final picked = await showSoliplexDatePicker(
          context: context,
          initialDate: _value,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
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
            : const Icon(Icons.calendar_today_outlined),
      ),
    );
  }
}
