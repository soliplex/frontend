import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../auth_tokens.dart';
import '../server_entry.dart';

/// A small sign-in status dot for an auth-required server:
///
/// - **green** (`success`) — signed in;
/// - **red** (`danger`) — not signed in (or expired).
///
/// Only meaningful for servers where `requiresAuth` is true: a no-auth server
/// is always ready, so callers omit the dot for those — but they keep a [size]
/// -wide slot for it, so titles line up whether or not a row has a dot. Reads
/// the per-entry session signal, so the dot lives in a [Watch] and updates on
/// sign-in / expiry without a server-map mutation. The tooltip carries the same
/// status as text for accessibility.
class ServerStatusDot extends StatelessWidget {
  const ServerStatusDot({super.key, required this.entry});

  /// Width the dot occupies. Public so a dotless row can reserve the same
  /// slot — `ListTile` drops `minLeadingWidth` and `horizontalTitleGap`
  /// entirely when `leading` is null, which would pull that title left.
  static const double size = 8;

  final ServerEntry entry;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final signedIn = entry.auth.session.value is ActiveSession;
      final color = signedIn ? context.success : context.danger;
      final label = signedIn ? 'Signed in' : 'Not signed in';
      return Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
    });
  }
}
