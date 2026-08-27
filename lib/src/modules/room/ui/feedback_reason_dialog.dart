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
    // The field was disabled while loading, so autofocus never took effect.
    _focusNode.requestFocus();
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
    // `mounted` does not say this route is still the one on top: the platform
    // back button pops a non-dismissible dialog, and this State stays mounted
    // for the whole pop transition, so popping again would take the screen
    // underneath with it.
    if (sent) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tell us why'),
      content: SoliplexInput(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        maxLines: 5,
        hintText: 'Add a reason (optional)',
        // The unread-note warning is the ordinary state, not an error, and it
        // has to outlive a failed submit — so the two occupy different slots.
        helperText: _unreadNote,
        errorText: _error,
        isLoading: _isLoading,
        // Not `isLoading` while submitting: that disables the field, greying
        // out the text the user may still need to retry with.
        readOnly: _isSubmitting,
        textInputAction: TextInputAction.newline,
      ),
      actions: [
        SoliplexButton.text(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
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
