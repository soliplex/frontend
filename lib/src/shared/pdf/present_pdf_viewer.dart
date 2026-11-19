import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../adaptive_surface.dart';

/// Shows a PDF viewer over the screen: as a dialog at tablet width and
/// wider, as a page of its own below it (see [presentAdaptively]).
///
/// [build] receives the viewer's own context — under its own scaffold, so a
/// snackbar it shows lands above a dialog's barrier rather than under it —
/// and a callback that closes it. Completes when it closes.
Future<void> presentPdfViewer(
  BuildContext context, {
  required Widget Function(BuildContext viewerContext, VoidCallback close)
      build,
}) =>
    presentAdaptively<void>(
      context,
      build: (asDialog) =>
          _PresentedPdfViewer(asDialog: asDialog, viewer: build),
    );

class _PresentedPdfViewer extends StatelessWidget {
  const _PresentedPdfViewer({required this.asDialog, required this.viewer});

  final bool asDialog;
  final Widget Function(BuildContext viewerContext, VoidCallback close) viewer;

  /// The widest a dialog grows, as the app's other viewer dialogs do.
  static const _dialogMaxWidth = 800.0;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    final framed = ScaffoldMessenger(
      child: Builder(
        builder: (viewerContext) => Scaffold(
          body: SafeArea(child: viewer(viewerContext, close)),
        ),
      ),
    );
    if (!asDialog) return framed;
    return Dialog(
      insetPadding: const EdgeInsets.all(SoliplexSpacing.s4),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _dialogMaxWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: framed,
      ),
    );
  }
}
