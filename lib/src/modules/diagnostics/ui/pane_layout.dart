import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';

/// What the list keeps when the controls cannot fit: roughly one collapsed
/// row of either pane's list, so a squeezed pane still shows something.
const double _minListExtent = 72;

/// A pane's controls above its list.
///
/// Controls are a fixed-height child of a column, so a viewport too short for
/// them — a phone in landscape, a large Dynamic Type setting — would overflow
/// rather than give way. Capping them at what is left over [_minListExtent]
/// and making them scrollable is what gives way instead. Until the viewport
/// is that short this changes nothing: the box takes its child's height.
///
/// The request filters are what reach that point in a viewport anyone would
/// use; the log heading rarely does. Both panes share this anyway, because
/// two panes laying out the same two slots two ways is how one of them ends
/// up with the bug the other already fixed.
///
/// Needs a bounded height: it hands one child the rest of the column.
class PaneLayout extends StatefulWidget {
  const PaneLayout({required this.controls, required this.list, super.key});

  /// What the list is guaranteed, however tall the controls grow.
  static const double minListExtent = _minListExtent;

  /// Whatever sits directly above the list and yields with it. A pane may
  /// stack something above [PaneLayout] itself — the concurrency strip does —
  /// and that keeps its own height, outside everything guaranteed here.
  ///
  /// Padded and width-capped here, so both panes get the same box.
  final Widget controls;

  /// The list, or whichever placeholder stands in for it.
  final Widget list;

  @override
  State<PaneLayout> createState() => _PaneLayoutState();
}

class _PaneLayoutState extends State<PaneLayout> {
  /// One controller for the scroll view and the [Scrollbar] that tracks it.
  /// Not optional: handing [SingleChildScrollView] a controller is also what
  /// stops it claiming the [PrimaryScrollController] the list below it takes,
  /// which two scrollables cannot share.
  final _controlsScroll = ScrollController();

  @override
  void dispose() {
    _controlsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        // The controls keep to their own width, so they sit at the pane's
        // left margin rather than floating in the middle of a wide window.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(0, constraints.maxHeight - _minListExtent),
            ),
            child: Scrollbar(
              // Visible at rest, not only mid-drag: a squeezed control block
              // with no thumb is indistinguishable from one that is cut off.
              thumbVisibility: true,
              controller: _controlsScroll,
              child: SingleChildScrollView(
                controller: _controlsScroll,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SoliplexSpacing.s4,
                    SoliplexSpacing.s4,
                    SoliplexSpacing.s4,
                    SoliplexSpacing.s2,
                  ),
                  // Capped so the controls do not stretch the width of a
                  // desktop window, and capped in one place so the two panes
                  // cannot disagree about how wide the same control is.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: SoliplexBreakpoints.tablet,
                    ),
                    child: widget.controls,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: widget.list),
        ],
      ),
    );
  }
}
