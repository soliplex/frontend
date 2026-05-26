import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/button/loading_indicator.dart';

/// One option in a [SoliplexDropdown].
class SoliplexDropdownEntry<T> {
  const SoliplexDropdownEntry({
    required this.value,
    required this.label,
    this.icon,
  });

  /// The value emitted via [SoliplexDropdown.onSelected] when this entry
  /// is picked.
  final T value;

  /// Plain-text label shown in the popup and (when selected) in the
  /// closed-state field.
  final String label;

  /// Optional leading icon shown beside the label in the popup.
  final Widget? icon;
}

/// Soliplex's branded select — a thin layer over Material 3's
/// [DropdownMenu].
///
/// Generic over [T] so the value type is preserved end-to-end. Mirrors
/// `SoliplexInput`'s opinionated axes:
///
/// - **`label` / `helperText` / `errorText`** — passed as plain strings;
///   the wrapper composes the `InputDecoration` internally.
/// - **`isLoading`** — disables interaction and swaps the trailing
///   chevron for a spinner. Useful during async option-loading.
/// - **`enabled`** — set false to disable interaction without showing
///   a spinner.
class SoliplexDropdown<T> extends StatelessWidget {
  const SoliplexDropdown({
    required this.entries,
    super.key,
    this.initialValue,
    this.onSelected,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.leadingIcon,
    this.enabled = true,
    this.isLoading = false,
    this.width,
  });

  final List<SoliplexDropdownEntry<T>> entries;

  /// Pre-selected value. Must match the [SoliplexDropdownEntry.value] of
  /// one of [entries] for the field to render with that label.
  final T? initialValue;

  final ValueChanged<T?>? onSelected;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? leadingIcon;
  final bool enabled;
  final bool isLoading;

  /// Pixel width of the closed field. Defaults to the natural width
  /// computed by [DropdownMenu] from its longest entry.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownMenu<T>(
      width: width,
      initialSelection: initialValue,
      enabled: enabled && !isLoading,
      onSelected: onSelected,
      label: label == null ? null : Text(label!),
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      leadingIcon: leadingIcon,
      trailingIcon: isLoading
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: ButtonLoadingIndicator(
                foregroundColor: scheme.onSurfaceVariant,
              ),
            )
          : null,
      dropdownMenuEntries: [
        for (final entry in entries)
          DropdownMenuEntry<T>(
            value: entry.value,
            label: entry.label,
            leadingIcon: entry.icon,
          ),
      ],
    );
  }
}
