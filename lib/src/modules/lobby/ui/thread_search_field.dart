import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../thread_query.dart';
import 'labels_view.dart' show LabelChip;

/// How long typing settles before the listing is refetched.
///
/// Long enough that typing a word costs one request rather than one per
/// keystroke, short enough that the list feels tied to the box.
const Duration kThreadSearchDebounce = Duration(milliseconds: 300);

/// The threads tab's search box: free text and `@label` in one field.
///
/// `Osprey Manual @manuals` narrows by name and by label at once; either
/// half works alone. Typing `@` opens a menu of matching labels, which
/// only ever *selects* — a user cannot coin a label from here, because
/// only administrators may create one.
class ThreadSearchField extends StatefulWidget {
  const ThreadSearchField({
    super.key,
    required this.labels,
    required this.onChanged,
  });

  /// The server's catalogue, for the suggestions.
  final List<ThreadLabel> labels;

  /// Fires with the parsed query once typing settles.
  final ValueChanged<ThreadQuery> onChanged;

  @override
  State<ThreadSearchField> createState() => _ThreadSearchFieldState();
}

class _ThreadSearchFieldState extends State<ThreadSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();

  Timer? _debounce;

  /// Labels matching the `@` token being typed, or empty when none is.
  List<ThreadLabel> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ThreadSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The catalogue can arrive after the field is built, or change while
    // the menu is open; recompute against whatever is current.
    if (!identical(oldWidget.labels, widget.labels)) _refreshSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _hide();
  }

  void _onChanged() {
    _refreshSuggestions();

    // Debounced so a word costs one request, not one per keystroke.
    _debounce?.cancel();
    _debounce = Timer(kThreadSearchDebounce, () {
      if (mounted) widget.onChanged(parseThreadQuery(_controller.text));
    });
  }

  void _refreshSuggestions() {
    final selection = _controller.selection;
    // A ranged or unset selection has no single cursor to read a token
    // at, so there is nothing to complete.
    final cursor =
        selection.isValid && selection.isCollapsed ? selection.baseOffset : -1;
    final token = activeLabelToken(_controller.text, cursor);

    if (token == null || !_focus.hasFocus) {
      _hide();
      return;
    }

    final already = parseThreadQuery(_controller.text).labelNames.toSet();
    final matches = [
      for (final label in widget.labels)
        // Case-folded on both sides, because label names ignore case —
        // matching literally would make '@Urgent' suggest nothing.
        if (label.name.toLowerCase().contains(token) &&
            !already.contains(label.name.toLowerCase()))
          label,
    ];

    setState(() => _suggestions = matches);
    if (matches.isEmpty) {
      _hide();
    } else {
      _overlay.show();
    }
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  void _complete(ThreadLabel label) {
    final selection = _controller.selection;
    final cursor = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : _controller.text.length;

    final completed = completeLabelToken(
      _controller.text,
      cursor,
      label.name.toLowerCase(),
    );
    if (completed == null) return;

    _controller.value = TextEditingValue(
      text: completed.text,
      selection: TextSelection.collapsed(offset: completed.cursor),
    );
    _hide();
    // Deliberately immediate rather than debounced: picking from the
    // menu is a decision, not typing.
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  void _onSubmitted(String _) {
    // Enter takes the first suggestion when the menu is open — otherwise
    // it would commit a half-typed '@man' as a label name that matches
    // nothing.
    if (_overlay.isShowing && _suggestions.isNotEmpty) {
      _complete(_suggestions.first);
      return;
    }
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  void _clear() {
    _controller.clear();
    _hide();
    _debounce?.cancel();
    widget.onChanged(ThreadQuery.empty);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildSuggestions,
      child: CompositedTransformTarget(
        link: _link,
        child: SoliplexInput(
          controller: _controller,
          focusNode: _focus,
          label: 'Search threads',
          hintText: 'Name, or @label',
          leadingIcon: const Icon(Icons.search),
          trailingIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: _clear,
                ),
          onSubmitted: _onSubmitted,
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // A full-screen catcher, so tapping anywhere else dismisses the
        // menu rather than leaving it floating over the list.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, SoliplexSpacing.s1),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(context.radii.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: SoliplexSpacing.s1,
                  ),
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final label = _suggestions[index];
                    return InkWell(
                      onTap: () => _complete(label),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SoliplexSpacing.s3,
                          vertical: SoliplexSpacing.s2,
                        ),
                        child: Row(
                          children: [
                            LabelChip(label: label),
                            const Spacer(),
                            if (label.usageCount != null)
                              Text(
                                '${label.usageCount}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
