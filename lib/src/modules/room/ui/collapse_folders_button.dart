import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';

import '../file_sort.dart';
import '../workspace_groups.dart';

/// Closes every folder of the workspace [listing], drawn as one segment in
/// the style of the sort bar it sits beside. Shows nothing for a workspace
/// without folders.
///
/// Disabled, with the reason in its tooltip and to a screen reader, while
/// [sort] shows no folders or no folder is open: the way the sort bar
/// treats an order it cannot apply.
class CollapseFoldersButton extends StatelessWidget {
  const CollapseFoldersButton({
    super.key,
    required this.listing,
    required this.sort,
    required this.folderToggles,
    required this.onCollapse,
  });

  static const _label = 'Collapse all folders';

  final List<WorkdirFile> listing;
  final FileSort sort;

  /// The folders the reader has opened or closed, by path, as the workspace
  /// list takes them.
  final Map<String, bool> folderToggles;

  /// Called with every open folder's path, at any depth.
  final ValueChanged<List<String>> onCollapse;

  @override
  Widget build(BuildContext context) {
    // Its order is irrelevant here; only which folders exist matters.
    final root = workspaceTree(listing, descending: false);
    if (root.folders.isEmpty) return const SizedBox.shrink();
    final unavailable = sort.key != FileSortKey.folders
        ? 'Folders show only under Folders'
        : !anyFolderOpen(root, folderToggles)
            ? 'No folder is open'
            : null;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(context.radii.md);
    return Tooltip(
      message: unavailable ?? _label,
      // The label below already says it; announced twice otherwise.
      excludeFromSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: unavailable == null
              ? () => onCollapse(openFolders(root, folderToggles))
              : null,
          borderRadius: radius,
          child: Semantics(
            button: true,
            enabled: unavailable == null,
            label: unavailable == null ? _label : '$_label: $unavailable',
            excludeSemantics: true,
            child: Container(
              // Fills the height its row gives it, the sort bar's, with the
              // icon centred.
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: radius,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s2,
                vertical: SoliplexSpacing.s1,
              ),
              child: Icon(
                Icons.unfold_less,
                size: 16,
                // Material's disabled foreground, as the sort bar's.
                color: unavailable == null
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
