import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'effective_marking.dart';
import 'pre_access_notice.dart';

/// Wraps the entire routed app with persistent classification chrome:
///
/// * a pre-access notice gate — no protected content renders until the
///   notice is acknowledged;
/// * a persistent top marking banner on every screen (compact on mobile);
/// * a bottom footer banner for classified contexts (confidential and
///   above), per the marking guidance that classified views reserve a
///   footer.
///
/// Installed once in the shell's `MaterialApp.router` builder slot so it
/// covers every route.
class MarkingAppChrome extends ConsumerWidget {
  const MarkingAppChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acknowledged =
        ref.watch(markingNoticeAcknowledgedProvider).watch(context);
    if (!acknowledged) return const PreAccessNotice();

    final marking = ref.watch(effectiveMarkingProvider);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < SoliplexBreakpoints.tablet;

    // Classified contexts (confidential and above) also carry a bottom
    // banner. CUI / UNCLASSIFIED show the top banner only.
    final showFooter = marking.severity >= DatasetMarking.confidential.severity;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: SoliplexMarkingBanner(marking: marking, compact: compact),
        ),
        // The banner consumed the top inset; strip it from descendants so
        // inner scaffolds don't pad for the status bar a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: showFooter,
            child: child,
          ),
        ),
        if (showFooter)
          SafeArea(
            top: false,
            child: SoliplexMarkingBanner(marking: marking, compact: compact),
          ),
      ],
    );
  }
}
