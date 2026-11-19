import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Shows a viewer the way the window has room for: as a dialog at
/// [SoliplexBreakpoints.tablet] width and wider, as a page of its own below
/// it.
///
/// [build] is told which it is building for, so it can frame itself: a
/// dialog brings its own size and close control, a page its own scaffold.
///
/// Both open and close with no transition: the default fade and slide read
/// as a flash when the user expects an immediate jump to what they tapped.
/// The dialog's barrier dismisses it.
Future<T?> presentAdaptively<T>(
  BuildContext context, {
  required Widget Function(bool asDialog) build,
}) {
  final asDialog =
      MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.tablet;
  final child = build(asDialog);

  if (asDialog) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => child,
    );
  }

  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => child,
    ),
  );
}
