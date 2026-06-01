import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/button/loading_indicator.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// Soliplex's branded text input — a thin layer over Material's
/// [TextFormField].
///
/// The widget is opinionated on the parts Material leaves to the caller:
///
/// 1. **Password mode** — set [isPassword] and the input obscures its
///    contents and grows a trailing eye-toggle button. No call-site
///    boilerplate for the show/hide state.
/// 2. **Loading mode** — set [isLoading] and the input disables itself
///    and shows a spinner in the trailing slot, useful during async
///    validation or form submission.
/// 3. **Label / helper / error** — passed as plain strings; the wrapper
///    composes the [InputDecoration].
///
/// Stays as form-aware ([TextFormField]) so call sites inside a [Form]
/// can use [validator]; standalone use also works.
class SoliplexInput extends StatefulWidget {
  const SoliplexInput({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.leadingIcon,
    this.trailingIcon,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.isPassword = false,
    this.isLoading = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
  });

  /// External text controller. Mutually exclusive with [initialValue].
  final TextEditingController? controller;

  /// External focus node. Lets callers drive focus programmatically
  /// (e.g. refocusing the field after a submit).
  final FocusNode? focusNode;

  /// One-time initial value. Use [controller] if you need to read or
  /// programmatically change the text after construction.
  final String? initialValue;

  /// Field label shown above the input (or as floating label).
  final String? label;

  /// Placeholder text inside the empty input.
  final String? hintText;

  /// Helper text shown below the input. Hidden when [errorText] is non-null.
  final String? helperText;

  /// Validation error shown in place of [helperText] and tinted with
  /// the theme's error color.
  final String? errorText;

  /// Optional leading icon.
  final Widget? leadingIcon;

  /// Optional trailing icon. Ignored when [isPassword] (replaced by the
  /// eye toggle) or [isLoading] (replaced by the spinner).
  final Widget? trailingIcon;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  /// Obscures the input and shows an eye toggle as the trailing icon.
  final bool isPassword;

  /// Disables the input and replaces the trailing icon with a spinner.
  final bool isLoading;

  /// Set false to disable both interaction and visual emphasis.
  final bool enabled;

  /// Locks editing while keeping the field's normal (non-disabled)
  /// styling. Unlike [enabled], the text stays fully legible and the
  /// field remains focusable — use it to freeze input during a
  /// transient busy state without greying the field out.
  final bool readOnly;

  /// Material's [TextField.maxLines]. Defaults to 1 (single-line).
  /// Set to `null` for unbounded multi-line growth.
  final int? maxLines;

  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  State<SoliplexInput> createState() => _SoliplexInputState();
}

class _SoliplexInputState extends State<SoliplexInput> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final obscure = widget.isPassword && !_showPassword;

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      initialValue: widget.initialValue,
      enabled: widget.enabled && !widget.isLoading,
      readOnly: widget.readOnly,
      obscureText: obscure,
      maxLines: obscure ? 1 : widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: widget.leadingIcon,
        suffixIcon: _suffix(scheme),
      ),
    );
  }

  /// Resolves the trailing widget for the current state:
  /// loading > password toggle > caller-provided trailingIcon.
  Widget? _suffix(ColorScheme scheme) {
    if (widget.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
        child: ButtonLoadingIndicator(foregroundColor: scheme.onSurfaceVariant),
      );
    }
    if (widget.isPassword) {
      return IconButton(
        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
        tooltip: _showPassword ? 'Hide password' : 'Show password',
        onPressed: () => setState(() => _showPassword = !_showPassword),
      );
    }
    return widget.trailingIcon;
  }
}
