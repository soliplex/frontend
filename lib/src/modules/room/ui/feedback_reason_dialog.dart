import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show ApiException, NetworkException;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.feedback_reason_dialog');

/// Collects the reason for a piece of feedback, and owns the whole exchange:
/// reading what is already on file, submitting, and reporting a submission
/// that did not land.
///
/// It owns that state because it lives in an overlay route rather than in the
/// message sliver, so — unlike a tile — it is not destroyed by scrolling past
/// the cache extent. A caller whose own state lives in the sliver still has to
/// guard its [onSubmit] against being called after that state is gone.
class FeedbackReasonDialog extends StatefulWidget {
  const FeedbackReasonDialog({
    required this.onSubmit,
    this.loadInitialText,
    super.key,
  });

  /// Submits [reason]. Returning false keeps this dialog open with the typed
  /// text intact so the user can retry; true closes it.
  final Future<bool> Function(String reason) onSubmit;

  /// Reads the note already on file, so the user extends or replaces it
  /// knowingly — the write is an upsert, so submitting over an unread note
  /// destroys it. Resolving null means nothing is on file; throwing means it
  /// could not be read, which is said out loud rather than shown as absence.
  ///
  /// Null when the caller has no note to read.
  final Future<String?> Function()? loadInitialText;

  @override
  State<FeedbackReasonDialog> createState() => _FeedbackReasonDialogState();
}

class _FeedbackReasonDialogState extends State<FeedbackReasonDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _unreadNote;
  String? _error;

  @override
  void initState() {
    super.initState();
    final load = widget.loadInitialText;
    if (load != null) {
      _isLoading = true;
      _load(load);
    }
  }

  Future<void> _load(Future<String?> Function() load) async {
    String? onFile;
    String? failure;
    try {
      onFile = await load();
    } on Object catch (error, stackTrace) {
      // The caller rethrows precisely so absence and unreadability stay
      // distinguishable; saying only "couldn't check" to the user would throw
      // that away, and a decode break would silently empty every prefill.
      _logger.warning(
        'Could not read the feedback already on file',
        error: error is NetworkException ? error : null,
        stackTrace: stackTrace,
        attributes: {
          if (error is ApiException) 'statusCode': error.statusCode,
          if (error is! NetworkException) 'failure': describeFailure(error),
        },
      );
      failure = "Couldn't check for an earlier note. "
          'Submitting replaces any that exists.';
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _unreadNote = failure;
      if (onFile != null) _controller.text = onFile;
    });
    // The field was disabled while loading, so autofocus never took effect and
    // the node still refuses focus until the rebuild above re-enables it —
    // hence after the frame, not now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not while covered: a modal scope keeps requesting focus even when it
      // is no longer on top, which would open the keyboard against whatever
      // route is above this one.
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) _focusNode.requestFocus();
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    bool sent;
    try {
      sent = await widget.onSubmit(_controller.text);
    } on Object catch (error, stackTrace) {
      // onSubmit is documented not to throw, so a throw here is a defect in
      // the caller rather than a rejected write. Without this the user is told
      // the send failed and no record says it was never attempted.
      _logger.error(
        'Feedback submit callback threw',
        error: error is NetworkException ? error : null,
        stackTrace: stackTrace,
        attributes: {
          if (error is ApiException) 'statusCode': error.statusCode,
          if (error is! NetworkException) 'failure': describeFailure(error),
        },
      );
      sent = false;
    }
    if (!mounted) return;
    if (sent) {
      // Close by identity, not by position. `mounted` does not say this route
      // is still on top: the platform back button pops a non-dismissible
      // dialog and this State stays mounted for the whole pop transition, so
      // `pop()` would take the screen underneath with it — and a route pushed
      // *over* this one reaches here too, where leaving the dialog behind
      // would show the user an unsent-looking dialog for a note already filed.
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else if (route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
      return;
    }
    setState(() {
      _isSubmitting = false;
      _error = "Couldn't send that. Try again.";
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Material's own `AlertDialog` maximum. Without a width the dialog sits at
  /// its 280 px minimum however wide the window is, because neither a text
  /// field nor this content states an intrinsic width preference. A `SizedBox`
  /// still yields to the incoming constraints, so a narrower window shrinks it
  /// rather than overflowing.
  static const _contentWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Tell us why'),
      content: SizedBox(
        width: _contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SoliplexInput(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: 5,
              hintText: 'Add a reason (optional)',
              errorText: _error,
              isLoading: _isLoading,
              // Not `isLoading` while submitting: that disables the field,
              // greying out the text the user may still need to retry with.
              readOnly: _isSubmitting,
              textInputAction: TextInputAction.newline,
            ),
            if (_unreadNote != null) ...[
              const SizedBox(height: SoliplexSpacing.s2),
              // Outside the input rather than its `helperText`: that slot is
              // capped at two lines, which ellipsizes away the clause naming
              // what a submit replaces, and `errorText` renders in place of it,
              // so a failed send would hide the warning at the moment the user
              // is most likely to send again.
              Text(
                _unreadNote!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        SoliplexButton.text(
          // Never disabled: the barrier is not dismissible and the send has no
          // deadline short enough to wait out, so this is the only way off a
          // request that hangs. It says Close rather than Cancel because a
          // send already dispatched keeps going — nothing here can recall it.
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        SoliplexButton.filled(
          onPressed: _isLoading || _isSubmitting ? null : _submit,
          isLoading: _isSubmitting,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
