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
const _defaultLabel = 'json';

/// The deepest nesting [JsonViewer] builds a tree for: building the tree and
/// its widgets and, on the web, decoding text each recurse once per level, so
/// much deeper nesting overflows the stack. That is why text is measured
/// before it is decoded. A scalar is depth 0, `[]` and `{}` are 1, `[[1]]` is
/// 2.
const maxJsonDepth = 100;

/// JSON under the shared header, with a Tree / Source switch.
///
/// The Source view is the text as written, or laid out with a 2-space indent,
/// every string and number as written, when [formatSource] is set; a
/// [JsonViewer.decoded] value is encoded and always laid out. The copy
/// button copies what the Source view shows. The Tree shows decoded values, so
/// `1e999` reads `Infinity` there, integers beyond 2^53 round on the web, and
/// on native platforms integers beyond the 64-bit range become doubles.
///
/// Oversized, too deeply nested ([maxJsonDepth]), invalid and empty content
/// shows its text under a notice, with no Tree. A decoded value JSON cannot
/// encode, such as `double.infinity`, shows only its Tree, with no notice,
/// and the copy button copies its `toString()`; past [maxHighlightedLength]
/// that text shows instead, as oversized. While [isStreaming], the invalid and
/// empty notices wait, since the text may be incomplete.
class JsonViewer extends StatefulWidget {
  /// JSON text, parsed once per change of [source]. [formatSource] is
  /// required: each site decides whether its text is shown as written.
  const JsonViewer.source(
    String this.source, {
    super.key,
    required this.initialView,
    this.label = _defaultLabel,
    required this.fill,
    required this.formatSource,
    this.selectable = true,
    this.isStreaming = false,
    this.showFailureNotice = true,
    this.maxBodyHeight,
  })  : value = null,
        assert(
          maxBodyHeight == null || !fill,
          'only an inline viewer caps its body',
        );

  /// A decoded JSON [value], encoded once per change of it, by identity:
  /// callers pass the same instance across rebuilds, or it is encoded and
  /// parsed again on each one. Its encoding always parses, so it never gets
  /// the invalid-JSON notice.
  const JsonViewer.decoded(
    this.value, {
    super.key,
    required this.initialView,
    this.label = _defaultLabel,
    required this.fill,
    this.selectable = true,
    this.maxBodyHeight,
  })  : source = null,
        formatSource = true,
        isStreaming = false,
        showFailureNotice = true,
        assert(
          maxBodyHeight == null || !fill,
          'only an inline viewer caps its body',
        );

  /// The JSON text; null for a [JsonViewer.decoded] value.
  final String? source;

  /// The decoded JSON value; null for [JsonViewer.source] text.
  final Object? value;

  /// The view shown first; [ContentView.rendered] is the Tree.
  final ContentView initialView;

  /// The header's text. It also names the copy button: `Copy JSON` for the
  /// default `json`, `Copy <label>` otherwise.
  final String label;

  /// Whether the Source view and the copy button show the JSON text laid out
  /// with a 2-space indent rather than exactly as written. When the laid-out
  /// text is longer than [maxHighlightedLength], the unlaid text shows
  /// instead, as plain text with no Tree, whatever this is: [source], or the
  /// compact encoding of a [JsonViewer.decoded] value. Always true for
  /// [JsonViewer.decoded].
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
  /// Always true for [JsonViewer.decoded].
  final bool showFailureNotice;

  /// When set, the inline body is clipped to at most this height; see
  /// [ContentFrame.maxBodyHeight].
  final double? maxBodyHeight;

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

/// A decoded value JSON cannot encode, within budget: its tree, shown with no
/// Source view, and its `toString()` for the copy button. Its nesting is not
/// measured against [maxJsonDepth].
final class _Unencodable extends _Shown {
  const _Unencodable(super.text, this.nodes);

  final List<JsonNode> nodes;
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
    if (old.source != widget.source || !identical(old.value, widget.value)) {
      _shown = _decide();
    }
  }

  _Shown _decide() {
    if (widget.source case final source?) return _decideText(source);
    final value = widget.value;
    final String encoded;
    try {
      encoded = jsonEncode(value);
    } on JsonUnsupportedObjectError {
      final text = value.toString();
      if (text.length > maxHighlightedLength) return _TooLarge(text);
      return _Unencodable(text, buildJsonTree(value));
    }
    return _decideText(encoded);
  }

  _Shown _decideText(String source) {
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
        copyTooltip: label == _defaultLabel ? 'Copy JSON' : 'Copy $label',
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
        _Unencodable() || _Tree() => null,
      },
      fill: widget.fill,
      maxBodyHeight: widget.maxBodyHeight,
      body: switch (shown) {
        _TooLarge() => _sourceView('plaintext'),
        _Invalid() || _TooDeep() => _sourceView('json'),
        _Unencodable(:final nodes) => _treeView(nodes),
        _Tree(:final nodes) when _view == ContentView.rendered =>
          _treeView(nodes),
        _Tree() => _sourceView('json'),
      },
    );
  }

  /// The Tree view of [nodes]. The code's surface, matching the Source view's
  /// background. A Material, so the rows' ink paints on it rather than beneath
  /// it.
  Widget _treeView(List<JsonNode> nodes) => Material(
        color: codeSurfaceColor(context),
        child: JsonTreeView(nodes: nodes, selectable: widget.selectable),
      );

  /// The Source view: the text shown, highlighted as [language].
  Widget _sourceView(String language) => CodeView(
        code: _shown.text,
        language: language,
        selectable: widget.selectable,
      );
}
