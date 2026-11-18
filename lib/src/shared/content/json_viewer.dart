import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../json_tree_model.dart';
import '../json_tree_view.dart';
import '../log_once.dart';
import 'code_view.dart';
import 'content_frame.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.json_viewer');

const _notice = "This isn't valid JSON; showing the source.";

const _prettyJson = JsonEncoder.withIndent('  ');

/// JSON under the shared header, with a Tree / Source switch.
///
/// The Source view is the 2-space pretty-print, and the copy button copies it.
/// Text that does not parse shows as it is, highlighted, with no switch and a
/// notice above it, unless [showFailureNotice] is false or [isStreaming], when
/// the text may still be incomplete. The failure is logged once per distinct
/// content, and not while streaming.
class JsonViewer extends StatefulWidget {
  /// An already-decoded JSON [value].
  const JsonViewer.decoded(
    this.value, {
    super.key,
    required this.initialView,
    this.label = 'json',
    required this.fill,
    this.selectable = true,
  })  : source = null,
        isStreaming = false,
        showFailureNotice = true;

  /// JSON text, parsed once per change of [source].
  const JsonViewer.source(
    String this.source, {
    super.key,
    required this.initialView,
    this.label = 'json',
    required this.fill,
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

class _JsonViewerState extends State<JsonViewer> {
  late ContentView _view = widget.initialView;

  /// The tree of valid JSON; null when [JsonViewer.source] does not parse.
  List<JsonNode>? _tree;

  /// What the Source view shows: the pretty-print, or the text that failed.
  String _text = '';

  FormatException? _failure;
  StackTrace? _failureStackTrace;

  @override
  void initState() {
    super.initState();
    _parse();
    _logFailure();
  }

  @override
  void didUpdateWidget(JsonViewer old) {
    super.didUpdateWidget(old);
    final contentChanged =
        old.source != widget.source || old.value != widget.value;
    if (contentChanged) _parse();
    // Streaming ending with the text unchanged is when its failure is final.
    if (contentChanged || old.isStreaming != widget.isStreaming) _logFailure();
  }

  void _parse() {
    final source = widget.source;
    if (source == null) {
      _show(widget.value);
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e, st) {
      _tree = null;
      _text = source;
      _failure = e;
      _failureStackTrace = st;
      return;
    }
    _show(decoded);
  }

  void _show(Object? value) {
    _tree = buildJsonTree(value);
    _text = _prettyJson.convert(value);
    _failure = null;
    _failureStackTrace = null;
  }

  void _logFailure() {
    final failure = _failure;
    if (failure == null || widget.isStreaming) return;
    final source = widget.source!;
    if (!isFirstOccurrence('json:${widget.label}:$source')) return;
    // jsonDecode's FormatException carries a window of the source, so it goes
    // through describeFailure rather than `error:`.
    _logger.debug(
      'json content failed to parse',
      stackTrace: _failureStackTrace,
      attributes: {
        'label': widget.label,
        'length': source.length,
        'failure': describeFailure(failure),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final label = widget.label;
    return ContentFrame(
      header: ContentHeader(
        label: label,
        copyText: _text,
        copyTooltip: label == 'json' ? 'Copy JSON' : 'Copy $label',
        view: tree == null ? null : _view,
        renderedLabel: 'Tree',
        onViewChanged: (view) => setState(() => _view = view),
      ),
      notice: tree == null && widget.showFailureNotice && !widget.isStreaming
          ? const RenderFailureNotice(message: _notice)
          : null,
      fill: widget.fill,
      body: tree != null && _view == ContentView.rendered
          // The code's surface, so switching views keeps one background.
          ? ColoredBox(
              color: codeTheme(context)['root']?.backgroundColor ??
                  Colors.transparent,
              child: JsonTreeView(nodes: tree, selectable: widget.selectable),
            )
          : CodeView(
              code: _text,
              language: 'json',
              selectable: widget.selectable,
            ),
    );
  }
}
