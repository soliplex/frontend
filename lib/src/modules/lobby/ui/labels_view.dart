import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../labels_state.dart';

/// The swatches offered by the colour editor.
///
/// Evenly spaced around the hue wheel rather than hand-picked, so they
/// stay distinguishable from one another and consistent with the tint a
/// room avatar gets. Twelve is enough to tell labels apart at a glance
/// without turning the picker into a colour-matching exercise.
const int _swatchCount = 12;

List<Color> _swatches(Brightness brightness) => [
      for (var i = 0; i < _swatchCount; i++)
        hueColor(i * (360 / _swatchCount), brightness),
    ];

/// Renders [color] as the `#RRGGBB` the server stores.
String _toHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// The colour to paint [label] with.
///
/// Falls back to a tint hashed from the name when the stored swatch does
/// not parse — a label with an unreadable colour is still a usable label,
/// and a blank chip would look like a rendering fault.
Color labelColor(ThreadLabel label, Brightness brightness) =>
    colorFromHex(label.color) ?? hashedHueColor(label.name, brightness);

/// A chip for one label, in the label's own colour.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, this.onDeleted});

  final ThreadLabel label;

  /// Shows a trailing close button when non-null.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return SoliplexChip.colored(
      label: Text(label.name),
      color: labelColor(label, Theme.of(context).brightness),
      onDeleted: onDeleted,
    );
  }
}

/// The lobby's label catalogue.
///
/// Only reachable by an administrator: the tab itself is absent for
/// everyone else (see `visibleLobbyTabs`), because every control here is
/// an administrator action and a read-only version would be a tab of
/// things you cannot do.
///
/// That is presentation, not authorization. An administrator can be
/// demoted while this page is open, so every write still handles the
/// server's refusal rather than assuming it will be honoured.
class LabelsView extends StatelessWidget {
  const LabelsView({
    super.key,
    required this.state,
    this.selectedLabelId,
  });

  final LabelsState state;

  /// A label to highlight on arrival, from `/lobby?tab=labels&label=7`.
  ///
  /// Set when the properties dialog jumps here to edit a specific label,
  /// so the user lands on the row they asked for rather than hunting for
  /// it in a long list.
  final int? selectedLabelId;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final labels = state.labels.value;
      return switch (labels) {
        LabelsLoading() => const Center(child: CircularProgressIndicator()),
        LabelsUnsupported() => const _LabelsMessage(
            icon: Icons.update,
            title: 'Labels need a newer server',
            detail: 'This server cannot store thread labels yet.',
          ),
        LabelsFailed() => _LabelsMessage(
            icon: Icons.error_outline,
            title: 'Could not load labels',
            detail: '${labels.error}',
            onRetry: state.refresh,
          ),
        LabelsLoaded() => _buildList(context, labels),
      };
    });
  }

  Widget _buildList(BuildContext context, LabelsLoaded loaded) {
    if (loaded.labels.isEmpty) {
      return _LabelsMessage(
        icon: Icons.label_outline,
        title: 'No labels yet',
        detail: 'Create one to start sorting threads by category.',
        onCreate: () => _create(context),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4,
            SoliplexSpacing.s2,
            SoliplexSpacing.s4,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SoliplexButton.outlined(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              child: const Text('New label'),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                vertical: SoliplexSpacing.s2,
              ),
              itemCount: loaded.labels.length,
              itemBuilder: (context, index) {
                final label = loaded.labels[index];
                return _LabelRow(
                  label: label,
                  highlighted: label.id == selectedLabelId,
                  onEdit: () => _edit(context, label),
                  onDelete: () => _delete(context, label),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LabelEditorDialog(state: state),
    );
  }

  Future<void> _edit(BuildContext context, ThreadLabel label) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LabelEditorDialog(state: state, existing: label),
    );
  }

  Future<void> _delete(BuildContext context, ThreadLabel label) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DeleteLabelDialog(state: state, label: label),
    );
  }
}

/// One catalogue row: the chip, its usage, and its controls.
class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.label,
    required this.highlighted,
    required this.onEdit,
    required this.onDelete,
  });

  final ThreadLabel label;
  final bool highlighted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = label.usageCount;

    return Container(
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
              child: Align(
            alignment: Alignment.centerLeft,
            child: LabelChip(label: label),
          )),
          // Absent for non-administrators, and absent is not zero: the
          // server withholds the number rather than reporting none.
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(right: SoliplexSpacing.s2),
              child: Text(
                count == 1 ? '1 thread' : '$count threads',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Create or rename-and-recolour a label.
class LabelEditorDialog extends StatefulWidget {
  const LabelEditorDialog({super.key, required this.state, this.existing});

  final LabelsState state;

  /// The label being edited, or null when creating a new one.
  final ThreadLabel? existing;

  @override
  State<LabelEditorDialog> createState() => _LabelEditorDialogState();
}

class _LabelEditorDialogState extends State<LabelEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  Color? _color;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) _color = colorFromHex(existing.color);
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _canSubmit => _name.text.trim().isNotEmpty && !_busy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final name = _name.text.trim();
    final color = _color == null ? null : _toHex(_color!);
    final existing = widget.existing;

    final reason = existing == null
        ? await widget.state.create(name: name, color: color)
        : await widget.state.update(existing.id, name: name, color: color);

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
    final swatches = _swatches(theme.brightness);
    // On create, nothing is chosen yet: leaving the colour null lets the
    // server derive one from the new label's own ID, which spreads hues
    // better than anything a picker default could.
    final selected = _color;

    return AlertDialog(
      title: Text(_isEditing ? 'Edit label' : 'New label'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SoliplexInput(
              label: 'Name',
              controller: _name,
              autofocus: true,
              onSubmitted: _canSubmit ? (_) => _submit() : null,
            ),
            const SizedBox(height: SoliplexSpacing.s4),
            Text('Colour', style: theme.textTheme.labelMedium),
            const SizedBox(height: SoliplexSpacing.s2),
            Wrap(
              spacing: SoliplexSpacing.s2,
              runSpacing: SoliplexSpacing.s2,
              children: [
                for (final swatch in swatches)
                  _Swatch(
                    color: swatch,
                    selected:
                        selected != null && _toHex(selected) == _toHex(swatch),
                    onTap: () => setState(() => _color = swatch),
                  ),
              ],
            ),
            if (!_isEditing && selected == null)
              Padding(
                padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
                child: Text(
                  'Leave unpicked and the server chooses one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: SoliplexSpacing.s4),
            Align(
              alignment: Alignment.centerLeft,
              child: SoliplexChip.colored(
                label: Text(
                  _name.text.trim().isEmpty ? 'Preview' : _name.text.trim(),
                ),
                color: selected ??
                    hashedHueColor(_name.text.trim(), theme.brightness),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
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
      actions: [
        SoliplexButton.text(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        SoliplexButton.text(
          onPressed: _canSubmit ? _submit : null,
          isLoading: _busy,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

/// One tappable colour in the editor's palette.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(context.radii.sm);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Colour ${_toHex(color)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirms deleting a label, warning when threads still carry it.
class _DeleteLabelDialog extends StatefulWidget {
  const _DeleteLabelDialog({required this.state, required this.label});

  final LabelsState state;
  final ThreadLabel label;

  @override
  State<_DeleteLabelDialog> createState() => _DeleteLabelDialogState();
}

class _DeleteLabelDialogState extends State<_DeleteLabelDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final reason = await widget.state.delete(widget.label.id);

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
    final count = widget.label.usageCount;

    return AlertDialog(
      title: const Text('Delete label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == null || count == 0
                ? 'Delete "${widget.label.name}"?'
                : 'Delete "${widget.label.name}"? It is still on '
                    '${count == 1 ? '1 thread' : '$count threads'}.',
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            'The threads themselves are not deleted.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        SoliplexButton.text(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        SoliplexButton.text(
          onPressed: _busy ? null : _submit,
          isLoading: _busy,
          intent: ButtonIntent.danger,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// A centered icon/title/detail block for the empty, error and
/// unsupported-server states.
class _LabelsMessage extends StatelessWidget {
  const _LabelsMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
    this.onCreate,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexButton.outlined(
                onPressed: () => onRetry!(),
                child: const Text('Retry'),
              ),
            ],
            if (onCreate != null) ...[
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexButton.filled(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                child: const Text('New label'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
