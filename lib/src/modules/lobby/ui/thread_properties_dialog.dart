import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show ThreadInfo, ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../labels_state.dart';
import 'labels_view.dart' show LabelChip, labelColor;

/// What a properties save has to do, from the dialog's point of view.
///
/// A function rather than a state object because two very different
/// screens open this dialog — the lobby's aggregated listing and a
/// room's thread sidebar — and they hold their threads in different
/// places. Each passes its own saver, which is also what folds the
/// result back into whatever list it owns.
///
/// Returns null on success or a human-readable reason on failure, so the
/// dialog can show it inline rather than throwing the user back to the
/// list.
typedef ThreadPropertiesSaver = Future<String?> Function({
  required String name,
  required String description,
  required List<int> labelIds,
});

/// Everything about a thread that a person can change.
///
/// Name, description and labels together in one dialog, deliberately:
/// `updateThreadMetadata` replaces the metadata row wholesale, so a
/// dialog that edited the name alone would have to remember to resend
/// the description or silently drop it.
class ThreadPropertiesDialog extends StatefulWidget {
  const ThreadPropertiesDialog({
    super.key,
    required this.thread,
    required this.labels,
    required this.onSave,
    this.onEditLabel,
  });

  final ThreadInfo thread;

  /// The server's catalogue, for the label picker.
  final LabelsState labels;

  final ThreadPropertiesSaver onSave;

  /// Jumps to the labels tab with this label selected. Absent for a user
  /// who has no labels tab to jump to.
  final void Function(int labelId)? onEditLabel;

  @override
  State<ThreadPropertiesDialog> createState() => _ThreadPropertiesDialogState();
}

class _ThreadPropertiesDialogState extends State<ThreadPropertiesDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.thread.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.thread.description);

  /// Selected label ids, seeded from the thread and edited in place.
  late final Set<int> _labelIds = {
    for (final label in widget.thread.labels) label.id,
  };

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onChanged)
      ..dispose();
    _description.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSubmit => _name.text.trim().isNotEmpty && !_busy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final reason = await widget.onSave(
      name: _name.text.trim(),
      description: _description.text.trim(),
      labelIds: _labelIds.toList(growable: false),
    );

    if (!mounted) return;
    if (reason == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Thread properties'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SoliplexInput(
                label: 'Name',
                controller: _name,
                autofocus: true,
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexInput(
                label: 'Description',
                controller: _description,
                maxLines: 3,
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              Text('Labels', style: theme.textTheme.labelMedium),
              const SizedBox(height: SoliplexSpacing.s2),
              Watch((context) => _buildPicker(context)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: SoliplexSpacing.s3),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        SoliplexButton.text(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        SoliplexButton.text(
          onPressed: _canSubmit ? _submit : null,
          isLoading: _busy,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final theme = Theme.of(context);
    final catalogue = widget.labels.current;

    if (catalogue.isEmpty) {
      return Text(
        'This server has no labels yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: SoliplexSpacing.s2,
      runSpacing: SoliplexSpacing.s2,
      children: [
        for (final label in catalogue)
          _SelectableLabel(
            label: label,
            selected: _labelIds.contains(label.id),
            onToggle: () => setState(() {
              if (!_labelIds.remove(label.id)) _labelIds.add(label.id);
            }),
            onEdit: widget.onEditLabel == null
                ? null
                : () {
                    // Leave first: the tab underneath is what the jump is
                    // for, and a dialog left open over it would hide it.
                    Navigator.pop(context);
                    widget.onEditLabel!(label.id);
                  },
          ),
      ],
    );
  }
}

/// One catalogue label, tappable to attach or detach.
///
/// Selected labels paint in their own colour; unselected ones are
/// outlined with a dot of it, so the set a thread carries reads at a
/// glance rather than having to be compared against the whole catalogue.
class _SelectableLabel extends StatefulWidget {
  const _SelectableLabel({
    required this.label,
    required this.selected,
    required this.onToggle,
    this.onEdit,
  });

  final ThreadLabel label;
  final bool selected;
  final VoidCallback onToggle;

  /// Jumps to the labels tab to edit this label. Null for a user with no
  /// labels tab, which is most of them.
  final VoidCallback? onEdit;

  @override
  State<_SelectableLabel> createState() => _SelectableLabelState();
}

class _SelectableLabelState extends State<_SelectableLabel> {
  bool _hovered = false;

  static bool get _isDesktop => switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.label;
    final color = labelColor(label, theme.brightness);

    final chip = Semantics(
      selected: widget.selected,
      button: true,
      child: widget.selected
          ? InkWell(onTap: widget.onToggle, child: LabelChip(label: label))
          : SoliplexChip.action(
              label: Text(label.name),
              icon: Icon(Icons.circle, color: color),
              onPressed: widget.onToggle,
            ),
    );

    final edit = widget.onEdit;
    if (edit == null) return chip;

    // Revealed on hover, so a catalogue of chips does not read as a row
    // of identical buttons competing with the labels themselves. There
    // is no hover to wait for on touch, so it stays put there.
    //
    // Still an explicit button rather than a right-click or long-press:
    // those would be invisible affordances on a chip nobody would think
    // to try, and this is the only route from a thread to a label's own
    // settings.
    final showEdit = _hovered || !_isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          // The slot is always occupied so the chips do not shuffle
          // sideways as the pointer crosses them.
          Visibility(
            visible: showEdit,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(
              icon: const Icon(Icons.tune, size: 16),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.only(left: SoliplexSpacing.s1),
              tooltip: 'Edit "${label.name}"',
              onPressed: showEdit ? edit : null,
            ),
          ),
        ],
      ),
    );
  }
}
