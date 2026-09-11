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
/// is always ready, so [leadingSlot] renders an empty slot for those instead.
/// Reads the per-entry session signal, so the dot lives in a [Watch] and
/// updates on sign-in / expiry without a server-map mutation. The tooltip
/// carries the same status as text for accessibility.
class ServerStatusDot extends StatelessWidget {
  const ServerStatusDot({super.key, required this.entry});

  static const double _size = 8;

  /// A server row's leading slot: the dot when [entry] needs a sign-in, an
  /// empty slot of the same width otherwise. Both server lists use this so the
  /// slot can never drift from the dot — `ListTile` drops `minLeadingWidth`
  /// and `horizontalTitleGap` entirely when `leading` is null, which would
  /// pull a dotless title left of its dotted neighbours.
  static Widget leadingSlot(ServerEntry entry) => SizedBox(
        width: _size,
        child: entry.requiresAuth ? ServerStatusDot(entry: entry) : null,
      );

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
          width: _size,
          height: _size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
    });
  }
}
