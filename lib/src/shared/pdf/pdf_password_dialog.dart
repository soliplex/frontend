import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Asks for the password of [documentTitle]. [retry] says the last one was
/// wrong. Returns null when the user cancels.
Future<String?> showPdfPasswordDialog(
  BuildContext context, {
  required String documentTitle,
  required bool retry,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _PdfPasswordDialog(
        documentTitle: documentTitle,
        retry: retry,
      ),
    );

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({required this.documentTitle, required this.retry});

  final String documentTitle;
  final bool retry;

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_password.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.retry
                ? 'That password did not open ${widget.documentTitle}. '
                    'Try again.'
                : '${widget.documentTitle} is protected with a password.',
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexInput(
            controller: _password,
            label: 'Password',
            isPassword: true,
            autofocus: true,
            errorText: widget.retry ? 'Incorrect password' : null,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        SoliplexButton.text(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        SoliplexButton.filled(
          onPressed: _submit,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
