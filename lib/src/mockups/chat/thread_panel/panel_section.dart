import 'package:flutter/widgets.dart';

/// Another mockup's take on the panel's first segment — what the thread
/// searches — in place of the stubbed database list.
class PanelSection {
  const PanelSection({
    required this.title,
    required this.icon,
    required this.summary,
    required this.handleCount,
    required this.body,
  });

  final String title;
  final IconData icon;

  /// The header's one line, kept useful while the segment is closed.
  final String summary;

  /// The count the collapsed panel's handle shows.
  final int handleCount;

  /// Given whatever height the other segments leave; scrolls itself.
  final WidgetBuilder body;
}

/// Where the screen is: the room, the open thread if any, and whether that
/// thread has started — its first message is what fixes what it searches.
/// [newThread] opens a fresh thread in the room, as the sidebar's New does.
typedef ThreadScope = ({
  String roomId,
  String? threadId,
  bool hasMessages,
  VoidCallback newThread,
});

/// What a mockup plugs into the chat screen to replace the panel's database
/// segment, and optionally to add a row above the composer.
class ThreadDatasetsSeam {
  const ThreadDatasetsSeam({
    required this.listenable,
    required this.section,
    this.composerAccessory,
  });

  /// Changes here rebuild the screen and the panel, sheet included.
  final Listenable listenable;
  final PanelSection Function(BuildContext context, ThreadScope scope) section;

  /// [openPanel] reveals the segment: the floating panel, or the sheet.
  final Widget? Function(
    BuildContext context,
    ThreadScope scope,
    VoidCallback openPanel,
  )? composerAccessory;
}
