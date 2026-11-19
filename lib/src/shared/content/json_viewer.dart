import 'dart:convert';

import 'package:flutter/material.dart';

import '../json_tree_model.dart';
import '../json_tree_view.dart';
import 'code_view.dart';
import 'content_frame.dart';
import 'json_text.dart';

const _failureNotice = "This isn't valid JSON; showing the source.";
const _emptyNotice = 'This JSON is empty.';
const _depthNotice = 'Too deeply nested for a tree; showing the source.';

/// The deepest nesting [JsonViewer] builds a tree for: building the tree and
/// its widgets and, on the web, decoding text each recurse once per level, so
/// much deeper nesting overflows the stack. That is why text is measured
/// before it is decoded. A scalar is depth 0, `[]` and `{}` are 1, `[[1]]` is
/// 2.
const maxJsonDepth = 100;

/// JSON under the shared header, with a Tree / Source switch.
///
/// The Source view is the text as written, or laid out with a 2-space indent,
/// every string and number as written, when [formatSource] is set. The copy
/// button copies what the Source view shows. The Tree shows decoded values, so
/// `1e999` reads `Infinity` there, integers beyond 2^53 round on the web, and
/// on native platforms integers beyond the 64-bit range become doubles.
///
/// Oversized, too deeply nested ([maxJsonDepth]), invalid and empty content
/// shows its text under a notice, with no Tree. While [isStreaming], the
/// invalid and empty notices wait, since the text may be incomplete.
class JsonViewer extends StatefulWidget {
  /// JSON text, parsed once per change of [source]. [formatSource] is
  /// required: each site decides whether its text is shown as written.
  const JsonViewer.source(
    this.source, {
    super.key,
    required this.initialView,
    this.label = 'json',
    required this.fill,
    required this.formatSource,
    this.selectable = true,
    this.isStreaming = false,
    this.showFailureNotice = true,
  });

  /// The JSON text.
  final String source;

  /// The view shown first; [ContentView.rendered] is the Tree.
  final ContentView initialView;

  /// The header's text. It also names the copy button: `Copy JSON` for the
  /// default `json`, `Copy <label>` otherwise.
  final String label;

  /// Whether the Source view and the copy button show [source] laid out with
  /// a 2-space indent rather than exactly as written. When the laid-out text
  /// is longer than [maxHighlightedLength], [source] shows instead, as plain
  /// text with no Tree, whatever this is.
  final bool formatSource;

  /// Whether the viewer takes the bounded height it is given, scrolling its
  /// body, rather than being as tall as its content; see [ContentFrame].
  final bool fill;

  /// Whether the viewer manages its own selection. Pass `false` inside a
  /// `SelectionArea` so the area handles selection.
  final bool selectable;

  /// Whether [source] may still be incomplete: a failure to parse shows no
  /// notice until this is false.
  final bool isStreaming;

  /// Whether text that does not parse gets the notice. A site that already
  /// explains the failure passes false. Empty text always gets its notice.
  final bool showFailureNotice;

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

/// What [JsonViewer] shows for its content, decided once per change of it.
sealed class _Shown {
  const _Shown(this.text);

  /// What the Source view shows, and the copy button copies.
  final String text;
}

/// Text past [maxHighlightedLength], as written or once laid out, shown as
/// plain text exactly as written.
final class _TooLarge extends _Shown {
  const _TooLarge(super.text);
}

/// Text that does not parse, shown highlighted.
final class _Invalid extends _Shown {
  const _Invalid(super.text);
}

/// JSON nesting deeper than [maxJsonDepth], shown as its text highlighted.
final class _TooDeep extends _Shown {
  const _TooDeep(super.text);
}

/// JSON within budget: its tree, and its Source view's text.
final class _Tree extends _Shown {
  const _Tree(super.text, this.nodes);

  final List<JsonNode> nodes;
}

class _JsonViewerState extends State<JsonViewer> {
  late ContentView _view = widget.initialView;

  late _Shown _shown;

  @override
  void initState() {
    super.initState();
    _shown = _decide();
  }

  @override
  void didUpdateWidget(JsonViewer old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _shown = _decide();
  }

  _Shown _decide() {
    final source = widget.source;
    if (source.length > maxHighlightedLength) return _TooLarge(source);
    if (jsonNestingDepth(source) > maxJsonDepth) return _TooDeep(source);
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return _Invalid(source);
    }
    // The tree's cost follows its rows, and the laid-out text has about one
    // line per row, so it is measured whether or not it is shown.
    final formatted = formatJson(source);
    if (formatted.length > maxHighlightedLength) return _TooLarge(source);
    return _Tree(
      widget.formatSource ? formatted : source,
      buildJsonTree(decoded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final label = widget.label;
    return ContentFrame(
      header: ContentHeader(
        label: label,
        copyText: shown.text,
        copyTooltip: label == 'json' ? 'Copy JSON' : 'Copy $label',
        view: shown is _Tree ? _view : null,
        renderedLabel: 'Tree',
        onViewChanged: (view) => setState(() => _view = view),
      ),
      notice: switch (shown) {
        _TooLarge() =>
          const ContentInfoNotice(message: tooLargeToHighlightNotice),
        _Invalid() when shown.text.trim().isEmpty => widget.isStreaming
            ? null
            : const ContentInfoNotice(message: _emptyNotice),
        _Invalid() when widget.showFailureNotice && !widget.isStreaming =>
          const ContentInfoNotice(message: _failureNotice),
        _Invalid() => null,
        _TooDeep() => const ContentInfoNotice(message: _depthNotice),
        _Tree() => null,
      },
      fill: widget.fill,
      body: switch (shown) {
        _TooLarge() => _sourceView('plaintext'),
        _Invalid() || _TooDeep() => _sourceView('json'),
        // The code's surface, so switching views keeps one background. A
        // Material, so the rows' ink paints on it rather than beneath it.
        _Tree(:final nodes) when _view == ContentView.rendered => Material(
            color: codeSurfaceColor(context),
            child: JsonTreeView(nodes: nodes, selectable: widget.selectable),
          ),
        _Tree() => _sourceView('json'),
      },
    );
  }

  /// The Source view: the text shown, highlighted as [language].
  Widget _sourceView(String language) => CodeView(
        code: _shown.text,
        language: language,
        selectable: widget.selectable,
      );
}
