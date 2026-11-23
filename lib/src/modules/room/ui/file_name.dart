import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'file_list_row.dart';
import 'file_preview/preview_kind.dart';

/// A file's or folder's [name] on one line, followed by [directory] in
/// muted text, ending in `/` so it reads as a folder, not as a tag on the
/// name.
///
/// The name is what a reader scans the list for, so the directory gives
/// way first: it is cut into whatever width the name leaves, keeping its
/// last folder (see [FolderPath]), and gets none once the name fills the
/// row. Wraps in a [FullNameTooltip], so the full [path] shows on hover or
/// long press and the text is not selectable.
class NameAndDirectory extends StatelessWidget {
  const NameAndDirectory({
    super.key,
    required this.path,
    required this.name,
    required this.directory,
    this.style,
  });

  /// The entry's path from the workspace root.
  final String path;

  /// The entry's name, which the caller keeps to one line and draws in
  /// [style].
  final Widget name;

  final String? directory;

  /// The name's style, which the directory takes muted.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final directory = this.directory;
    final directoryStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Align lets the row size to its content (instead of being stretched
        // by the parent Expanded), so the Tooltip anchors to the painted name
        // and directory and appears near the cursor.
        return Align(
          alignment: Alignment.centerLeft,
          child: FullNameTooltip(
            name: path,
            // The label announces the full path once: the texts would read
            // the name, then the directory apart from it.
            child: Semantics(
              label: path,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      // A Row leaves an inflexible child's width unbounded;
                      // the name may take the whole row, but no more.
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: name,
                    ),
                    if (directory != null)
                      Flexible(
                        child: Padding(
                          padding:
                              const EdgeInsets.only(left: SoliplexSpacing.s2),
                          child: FolderPath(
                            directory,
                            endsWithSlash: true,
                            style: directoryStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A file name on one line that, when cut, shortens its middle.
///
/// The end of a name is the most informative part of a cut one: names an
/// agent writes often differ only just before the extension, as dates and
/// versions do. So the end [splitForCut] keeps stays whole while it fits
/// beside the room the cut head keeps (see [_TwoPartLine]):
/// `quarterly_report_final.xlsx` reads `quarterly_r…_final.xlsx`. Flutter
/// lays out and ellipsizes both parts, and that room is measured as a
/// [Text] paints it, so the cut follows the text scale and bold-text
/// settings. Announces the whole name to a screen reader.
class FileName extends StatelessWidget {
  FileName(this.name, {super.key, this.style})
      : assert(!name.contains('/'), 'FileName takes a basename, not a path');

  /// A basename, not a path: a row shows a file's directory apart from its
  /// name.
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (head, end) = splitForCut(name);
    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: _TwoPartLine(
          head: head,
          style: style,
          end: _cutLine(end, style),
        ),
      ),
    );
  }
}

/// A folder's path on one line that, when cut, keeps its last folder whole:
/// `project/src/core` reads `project/s…/core`, and `raw/archive/2023`
/// reads `raw/a…/2023`. A last folder too long alone loses its middle, as a
/// [FileName] does: `p…/experiment_r…_11_05`. The folders above it give way
/// first, down to their first character and an ellipsis, then the last
/// folder's head (see [splitPathForCut]).
///
/// Leaves the path's announcement to its row, which names the whole path.
class FolderPath extends StatelessWidget {
  const FolderPath(
    this.path, {
    super.key,
    required this.endsWithSlash,
    this.style,
  });

  /// One folder's name, or a path of folders.
  final String path;

  /// Whether a `/` follows the last folder, so the path reads as the folder
  /// holding what comes before it on the row.
  final bool endsWithSlash;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (above, lastHead, lastTail) = splitPathForCut(path);
    return _TwoPartLine(
      head: above,
      style: style,
      end: _TwoPartLine(
        head: lastHead,
        style: style,
        end: _cutLine(endsWithSlash ? '$lastTail/' : lastTail, style),
      ),
    );
  }
}

/// [head] in [style], then [end], on one line: when the line is too narrow,
/// [head] is cut first, down to its first character and an ellipsis, and
/// [end] only once it is wider than the line less that room. The room keeps
/// the cut showing rather than the line starting at [end]: a slot as wide as
/// the ellipsis alone paints nothing.
class _TwoPartLine extends StatelessWidget {
  const _TwoPartLine({
    required this.head,
    required this.style,
    required this.end,
  });

  final String head;
  final TextStyle? style;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    final kept = head.isEmpty
        ? 0.0
        : _width(context, '${head.characters.first}\u2026', style);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: _cutLine(head, style)),
          ConstrainedBox(
            // A slot narrower than the end cuts it rather than overflowing.
            constraints: BoxConstraints(
              maxWidth: math.max(0, constraints.maxWidth - kept),
            ),
            child: end,
          ),
        ],
      ),
    );
  }
}

/// The width of [text] as a [Text] in [style] paints it here: with the
/// ambient style, text scale and bold-text setting it inherits.
double _width(BuildContext context, String text, TextStyle? style) {
  var effective = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // Rounded up, so the head's slot is never a fraction short of the text.
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

Text _cutLine(String text, TextStyle? style) => Text(
      text,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      // As wide as the text it paints: a cut line would otherwise keep its
      // slot's width, leaving a gap between the ellipsis and the end.
      textWidthBasis: TextWidthBasis.longestLine,
    );

/// How many of a name's last characters a cut keeps, before any extension.
const _keptEndCharacters = 6;

/// Splits the basename [name] into the head a cut shortens and the end it
/// keeps: the last [_keptEndCharacters] characters of the stem, then the
/// extension (see [splitExtension]).
(String, String) splitForCut(String name) {
  final (stem, extension) = splitExtension(name);
  final (head, tail) = _splitEnd(stem);
  return (head, '$tail$extension');
}

/// Splits the folder path [path] into the parts a cut gives up in turn: the
/// folders above the last, then the last folder's head, while its last
/// [_keptEndCharacters] characters stay. A folder name has no extension to
/// split off: `v1.2` is a version. The `/` before the last folder starts
/// its head, or its kept end when the head is empty, so it shows whenever
/// the folders above it do.
(String, String, String) splitPathForCut(String path) {
  final slash = path.lastIndexOf('/');
  final (head, tail) = _splitEnd(path.substring(slash + 1));
  if (slash < 0) return ('', head, tail);
  final above = path.substring(0, slash);
  return head.isEmpty ? (above, '', '/$tail') : (above, '/$head', tail);
}

/// Splits [text] before its last [_keptEndCharacters] characters, counting
/// characters as a reader sees them, so no emoji or accented letter is split.
(String, String) _splitEnd(String text) {
  final characters = text.characters;
  return (
    characters.skipLast(_keptEndCharacters).string,
    characters.takeLast(_keptEndCharacters).string,
  );
}

/// Splits the basename [name] into its stem and its extension, dot included.
///
/// A name with no extension (see [extensionOf]), or with one of more than 8
/// characters, which is not worth keeping whole, yields the name as the stem
/// and an empty extension.
(String, String) splitExtension(String name) {
  final extension = extensionOf(name);
  if (extension == null || extension.length > 8) return (name, '');
  final dot = name.length - extension.length - 1;
  return (name.substring(0, dot), name.substring(dot));
}
