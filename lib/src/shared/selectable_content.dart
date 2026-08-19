import 'package:flutter/material.dart';

/// Makes the text inside [child] selectable with a drag.
///
/// Place this *above* any tap handler in [child]. A selection widget wins the
/// gesture arena, so one sitting under a handler leaves that region dead to
/// taps; from above, a tap still reaches the handler and a drag selects.
class SelectableContent extends StatefulWidget {
  const SelectableContent({required this.child, super.key});

  final Widget child;

  @override
  State<SelectableContent> createState() => _SelectableContentState();
}

class _SelectableContentState extends State<SelectableContent> {
  // A bare SelectionArea takes a focusable node that paints nothing, so
  // keyboard traversal stops on an invisible target between the real controls.
  final FocusNode _focusNode = FocusNode(
    skipTraversal: true,
    debugLabel: 'SelectableContent',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionArea(focusNode: _focusNode, child: widget.child);
}
