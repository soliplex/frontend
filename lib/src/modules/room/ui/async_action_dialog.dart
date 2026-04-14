import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../../../../soliplex_frontend.dart';

/// Dialog that runs an async action with loading/error states.
///
/// Shows a spinner while in progress, inline error on failure,
/// and pops itself on success.
class AsyncActionDialog extends StatefulWidget {
  const AsyncActionDialog({
    super.key,
    required this.title,
    required this.contentBuilder,
    required this.actionLabel,
    required this.onAction,
    this.isDestructive = false,
    this.canSubmit = true,
  });

  final String title;

  /// Builds the dialog body. Receives a submit callback that is non-null
  /// when the action can be triggered (canSubmit is true and not busy).
  final Widget Function(VoidCallback? onSubmit) contentBuilder;
  final String actionLabel;
  final Future<void> Function() onAction;
  final bool isDestructive;

  /// External gate (e.g., text field validation). The action button is
  /// disabled when false, independent of the in-progress state.
  final bool canSubmit;

  @override
  State<AsyncActionDialog> createState() => _AsyncActionDialogState();
}

class _AsyncActionDialogState extends State<AsyncActionDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAction();
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      debugPrint('${widget.title} failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'async_action_dialog',
        context: ErrorDescription('during ${widget.title}'),
      ));
      if (mounted) {
        setState(() {
          _busy = false;
          _error = kDebugMode ? 'BUG: $e' : 'An unexpected error occurred.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.contentBuilder(
            widget.canSubmit && !_busy ? _run : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
            child: SizedBox(
              width: SoliplexSpacing.s4,
              height: SoliplexSpacing.s4,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          FilledButton(
            onPressed: widget.canSubmit ? _run : null,
            style: widget.isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            child: Text(widget.actionLabel),
          ),
      ],
    );
  }
}

/// Rename dialog: wraps [AsyncActionDialog] with a pre-filled text field.
class RenameDialog extends StatefulWidget {
  const RenameDialog({
    super.key,
    required this.initialName,
    required this.onAction,
  });

  final String initialName;
  final Future<void> Function(String name) onAction;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _controller;

  bool get _canSave =>
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim() != widget.initialName;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncActionDialog(
      title: 'Rename Thread',
      actionLabel: 'Save',
      canSubmit: _canSave,
      onAction: () => widget.onAction(_controller.text.trim()),
      contentBuilder: (onSubmit) => SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Thread name'),
          onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        ),
      ),
    );
  }
}
