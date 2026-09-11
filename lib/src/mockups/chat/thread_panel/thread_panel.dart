import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'context_tab.dart';
import 'panel_state.dart';
import 'workspace_tab.dart';

/// The floating thread panel: tabs for what shapes the thread's context and
/// for the workspace, collapsible to a handle.
///
/// Floats over the chat area rather than taking a fourth column so it reads
/// as belonging to the *thread*, where the rail, sidebar and header belong to
/// the room. Place it inside the chat area with an [Align] at the top-right;
/// it sizes itself to the space it is given.
class ThreadPanel extends StatefulWidget {
  const ThreadPanel({required this.state, super.key});

  final ThreadPanelState state;

  /// Width the open panel prefers. Narrower viewports get what is left.
  static const preferredWidth = 400.0;

  /// How far the panel fades while the pointer is elsewhere: present enough
  /// to be read at a glance, faint enough that the conversation stays the
  /// subject of the page. Full opacity returns on hover.
  static const restingOpacity = 0.55;

  @override
  State<ThreadPanel> createState() => _ThreadPanelState();
}

class _ThreadPanelState extends State<ThreadPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width =
              math.min(ThreadPanel.preferredWidth, constraints.maxWidth);
          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedOpacity(
              // Only the open panel fades; the handle is already small and
              // has to be found before it can be hovered.
              opacity:
                  _hovered || !state.isOpen ? 1 : ThreadPanel.restingOpacity,
              duration: const Duration(milliseconds: 180),
              // The card stays in the tree while collapsed, offstage, so
              // what was open, how far each list was scrolled and what was
              // typed in the workspace are all there again on reopen —
              // in memory only, for as long as the screen lives.
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Offstage(
                    offstage: !state.isOpen,
                    child: _PanelCard(
                      state: state,
                      width: width,
                      height: constraints.maxHeight,
                    ),
                  ),
                  if (!state.isOpen) _PanelHandle(state: state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The surface both states share.
///
/// The page's own ground, framed by a hairline and lifted by a soft shadow —
/// not a lighter tone. A raised tone would make the panel the brightest
/// block on the page, and it is a support panel: it should sit beside the
/// conversation, not above it.
class _FloatingSurface extends StatelessWidget {
  const _FloatingSurface({required this.child, this.shape});

  final Widget child;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shadowColor: scheme.shadow.withValues(alpha: 0.35),
      elevation: 6,
      shape: shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.lg),
            side: BorderSide(color: scheme.outlineVariant),
          ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// The open panel: the full height it is given, so the segments inside can
/// be allotted that height by their own rules (see [ContextTab]).
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.state,
    required this.width,
    required this.height,
  });

  final ThreadPanelState state;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: _FloatingSurface(
        child: ThreadPanelBody(state: state, onClose: state.toggleOpen),
      ),
    );
  }
}

/// The tabs and their content — what the floating card and the phone sheet
/// have in common. Needs a bounded height.
class ThreadPanelBody extends StatelessWidget {
  const ThreadPanelBody({required this.state, this.onClose, super.key});

  final ThreadPanelState state;

  /// What the header's trailing button does; null hides it. The floating
  /// card collapses, the sheet leaves it to its own dismissal.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelHeader(state: state, onClose: onClose),
        // Both tabs stay alive so switching away and back finds them
        // as they were.
        Expanded(
          child: IndexedStack(
            index: state.tab,
            children: [
              ContextTab(state: state),
              WorkspaceTab(state: state),
            ],
          ),
        ),
      ],
    );
  }
}

/// The panel as a modal sheet, for viewports too narrow to float it beside
/// the conversation. Same body, same state — so what was open, scrolled or
/// typed is there again the next time the sheet opens.
Future<void> showThreadPanelSheet(
  BuildContext context, {
  required ThreadPanelState state,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ThreadPanelBody(state: state),
      ),
    ),
  );
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.state, required this.onClose});

  final ThreadPanelState state;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: _PanelTab(
                  icon: Icons.data_usage,
                  label: 'Context',
                  selected: state.tab == 0,
                  onTap: () => state.tab = 0,
                ),
              ),
              Flexible(
                child: _PanelTab(
                  icon: Icons.forum_outlined,
                  label: 'Workspace',
                  selected: state.tab == 1,
                  onTap: () => state.tab = 1,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
            child: IconButton(
              icon: const Icon(Icons.close_fullscreen, size: 16),
              color: Theme.of(context).colorScheme.outline,
              tooltip: 'Collapse',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
            ),
          ),
      ],
    );
  }
}

/// One tab: icon, label, and a primary underline when selected.
class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4,
          vertical: SoliplexSpacing.s3,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: SoliplexSpacing.s2),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed panel: a pill that reopens it, with the count of connected
/// databases so the thread's footing is visible at a glance.
class _PanelHandle extends StatelessWidget {
  const _PanelHandle({required this.state});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = state.connectedDatabaseCount;
    return _FloatingSurface(
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      child: Tooltip(
        message: 'Open thread panel',
        child: InkWell(
          onTap: state.toggleOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s3,
              vertical: SoliplexSpacing.s2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_full,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: SoliplexSpacing.s2),
                Icon(Icons.storage, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: SoliplexSpacing.s1),
                Text(
                  '$connected',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
