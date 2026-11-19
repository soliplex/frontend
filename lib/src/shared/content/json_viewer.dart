import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../json_tree_model.dart';
import '../json_tree_view.dart';
import '../log_once.dart';
import 'code_view.dart';
import 'content_frame.dart';
import 'json_text.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.json_viewer');

const _failureNotice = "This isn't valid JSON; showing the source.";
const _depthNotice = 'Too deeply nested for a tree; showing the source.';

const _prettyJson = JsonEncoder.withIndent('  ');

/// The deepest nesting [JsonViewer] builds a tree for: building the tree and
/// its widgets, re-encoding a decoded value, and, on the web, decoding text
/// each recurse once per level, so much deeper nesting overflows the stack.
/// That is why text is measured before it is decoded. A scalar is depth 0, `[]`
/// and `{}` are 1, `[[1]]` is 2.
const maxJsonDepth = 100;

/// JSON under the shared header, with a Tree / Source switch.
///
/// The Source view is the text as written, or laid out with a 2-space indent,
/// every string and number as written, when [formatSource] is set; for a
/// decoded value it is the 2-space pretty-print. The copy button copies whatever
/// the Source view shows. The Tree shows decoded values, so `1e999` reads
/// `Infinity` there, integers beyond 2^53 round on the web, and on native
/// platforms integers beyond the 64-bit range become doubles.
///
/// Text that does not parse shows as it is, highlighted, with no switch and a
/// notice above it, unless [showFailureNotice] is false or [isStreaming], when
/// the text may still be incomplete. The failure is logged once per process
/// for each label and content pair, and never while streaming.
///
/// Content beyond the viewer's budget gets no switch and a neutral notice
/// instead, checked in this order: text longer than [maxHighlightedLength]
/// shows as plain text, unparsed; nesting deeper than [maxJsonDepth] shows the
/// text highlighted, measured before parsing, so text that is also invalid
/// gets this notice rather than the failure notice; and a Source view longer
/// than [maxHighlightedLength] shows as plain text.
class JsonViewer extends StatefulWidget {
  /// An already-decoded JSON [value], which must be what `jsonDecode` returns:
  /// anything else may not encode. Keep the same instance across rebuilds; a
  /// new instance is re-encoded and its tree rebuilt.
  ///
  /// There is no text to fall back on, so a [value] nesting deeper than
  /// [maxJsonDepth] shows only the notice, over an empty Source view.
  const JsonViewer.decoded(
    this.value, {
    super.key,
    required this.initialView,
    this.label = 'json',
    required this.fill,
    this.selectable = true,
  })  : source = null,
        isStreaming = false,
        showFailureNotice = true,
        formatSource = true;

  /// JSON text, parsed once per change of [source]. [formatSource] is
  /// required: each site decides whether its text is shown as written.
  const JsonViewer.source(
    String this.source, {
    super.key,
    required this.initialView,
    this.label = 'json',
    required this.fill,
    required this.formatSource,
    this.selectable = true,
    this.isStreaming = false,
    this.showFailureNotice = true,
  }) : value = null;

  /// The decoded value; unused when [source] is set.
  final Object? value;

  /// The JSON text, or null for a decoded [value].
  final String? source;

  /// The view shown first; [ContentView.rendered] is the Tree.
  final ContentView initialView;

  /// The header's text. It also names the copy button: `Copy JSON` for the
  /// default `json`, `Copy <label>` otherwise.
  final String label;

  /// Whether the Source view and the copy button show [source] laid out with
  /// a 2-space indent rather than exactly as written. A decoded value is always
  /// pretty-printed. When the laid-out text is longer than
  /// [maxHighlightedLength], [source] shows instead.
  final bool formatSource;

  /// Whether the viewer takes the bounded height it is given, scrolling its
  /// body, rather than being as tall as its content; see [ContentFrame].
  final bool fill;

  /// Whether the viewer manages its own selection. Pass `false` inside a
  /// `SelectionArea` so the area handles selection.
  final bool selectable;

  /// Whether [source] may still be incomplete: a failure to parse shows no
  /// notice and is not logged until this is false.
  final bool isStreaming;

  /// Whether text that does not parse gets the notice. A site that already
  /// explains the failure passes false.
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

/// Text past [maxHighlightedLength], shown as plain text.
final class _TooLarge extends _Shown {
  const _TooLarge(super.text);
}

/// Text that does not parse, shown highlighted.
final class _Invalid extends _Shown {
  const _Invalid(super.text, this.failure, this.stackTrace);

  final FormatException failure;
  final StackTrace stackTrace;
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

/// Whether [value] nests deeper than [maxJsonDepth], measured with an explicit
/// stack so that the measuring cannot overflow either.
bool _nestsTooDeep(Object? value) {
  final pending = <(Object?, int)>[(value, 0)];
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    final children = switch (node) {
      List() => node,
      Map() => node.values,
      _ => null,
    };
    if (children == null) continue;
    if (depth + 1 > maxJsonDepth) return true;
    for (final child in children) {
      pending.add((child, depth + 1));
    }
  }
  return false;
}

class _JsonViewerState extends State<JsonViewer> {
  late ContentView _view = widget.initialView;

  late _Shown _shown;

  @override
  void initState() {
    super.initState();
    _shown = _decide();
    _logFailure();
  }

  @override
  void didUpdateWidget(JsonViewer old) {
    super.didUpdateWidget(old);
    final contentChanged =
        old.source != widget.source || old.value != widget.value;
    if (contentChanged) _shown = _decide();
    // Streaming ending with the text unchanged is when its failure is final.
    if (contentChanged || old.isStreaming != widget.isStreaming) _logFailure();
  }

  _Shown _decide() {
    final source = widget.source;
    if (source == null) return _decideDecoded(widget.value);
    if (source.length > maxHighlightedLength) return _TooLarge(source);
    if (jsonNestingDepth(source) > maxJsonDepth) return _TooDeep(source);
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e, st) {
      return _Invalid(source, e, st);
    }
    final text = widget.formatSource ? formatJson(source) : source;
    return _treeWithin(text, decoded, ifTooLarge: source);
  }

  /// Decides for a decoded [value], which has no text of its own.
  _Shown _decideDecoded(Object? value) {
    if (_nestsTooDeep(value)) return const _TooDeep('');
    final text = _prettyJson.convert(value);
    return _treeWithin(text, value, ifTooLarge: text);
  }

  /// The tree of [value] with [text] as its Source view, unless [text] is
  /// longer than [maxHighlightedLength]: then [ifTooLarge] shown plain. Laid
  /// out, text can be far longer than the source it came from.
  _Shown _treeWithin(
    String text,
    Object? value, {
    required String ifTooLarge,
  }) =>
      text.length > maxHighlightedLength
          ? _TooLarge(ifTooLarge)
          : _Tree(text, buildJsonTree(value));

  void _logFailure() {
    final shown = _shown;
    if (shown is! _Invalid || widget.isStreaming) return;
    final source = shown.text;
    if (!isFirstOccurrence('json:${widget.label}:$source')) return;
    // jsonDecode's FormatException carries a window of the source, so it goes
    // through describeFailure rather than `error:`.
    _logger.debug(
      'json content failed to parse',
      stackTrace: shown.stackTrace,
      attributes: {
        'label': widget.label,
        'length': source.length,
        'failure': describeFailure(shown.failure),
      },
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
        _Invalid() when widget.showFailureNotice && !widget.isStreaming =>
          const RenderFailureNotice(message: _failureNotice),
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
