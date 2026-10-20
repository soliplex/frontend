import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../classification_levels.dart';
import '../model.dart';
import '../store.dart';
import 'common.dart';

/// Free-text tags with the values already in use one tap away, so the
/// vocabulary converges without an official list behind it.
class TagField extends StatefulWidget {
  const TagField({
    required this.label,
    required this.values,
    required this.suggestions,
    required this.onChanged,
    super.key,
    this.hintText,
  });

  final String label;
  final String? hintText;
  final Set<String> values;
  final List<String> suggestions;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<TagField> createState() => _TagFieldState();
}

class _TagFieldState extends State<TagField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  void _add(String value) {
    final v = value.trim();
    _controller.clear();
    if (v.isEmpty || widget.values.contains(v)) return;
    widget.onChanged({...widget.values, v});
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<String>(
          textEditingController: _controller,
          focusNode: _focus,
          optionsBuilder: (value) {
            final text = value.text.trim().toLowerCase();
            // Only while typing: an empty field showing every value would
            // cover the form below it.
            if (text.isEmpty) return const <String>[];
            return widget.suggestions
                .where(
                  (s) =>
                      !widget.values.contains(s) &&
                      s.toLowerCase().contains(text),
                )
                .take(8);
          },
          onSelected: _add,
          fieldViewBuilder: (context, controller, focus, _) => SoliplexInput(
            controller: controller,
            focusNode: focus,
            label: widget.label,
            hintText: widget.hintText ?? 'Type and press Enter',
            onSubmitted: _add,
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(context.radii.md),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 240, maxWidth: 360),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        title: Text(o),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s2,
            children: [
              for (final v in widget.values)
                SoliplexChip(
                  label: Text(v),
                  onDeleted: () =>
                      widget.onChanged({...widget.values}..remove(v)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A dialog that is a dialog when there is room and the whole screen when
/// there is not.
Future<T?> _showAdaptiveDialog<T>(
  BuildContext context,
  Widget Function(BuildContext context) builder, {
  double width = 640,
}) {
  final store = DatasetsScope.read(context);
  final narrow = MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
  return showDialog<T>(
    context: context,
    builder: (context) {
      final child =
          DatasetsScope(store: store, child: Builder(builder: builder));
      if (narrow) return Dialog.fullscreen(child: child);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 760),
          child: child,
        ),
      );
    },
  );
}

/// Shares a dataset: who gets it, the tags it needs to be found, and the
/// owner's word that everyone picked may have it.
Future<void> showShareDialog(BuildContext context, Dataset dataset) =>
    _showAdaptiveDialog(context, (_) => _ShareDialog(dataset: dataset));

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.dataset});

  final Dataset dataset;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final Set<String> _audience = {...widget.dataset.audience};
  late Set<String> _keywords = {...widget.dataset.tags.keywords};
  late Set<String> _systems = {...widget.dataset.tags.systems};
  late Set<String> _affiliations = {...widget.dataset.tags.affiliations};
  String _search = '';
  bool _attested = false;

  DatasetTags get _tags => DatasetTags(
      keywords: _keywords, systems: _systems, affiliations: _affiliations);

  bool _cleared(Principal p) =>
      p.kind == PrincipalKind.group ||
      isWithin(widget.dataset.level, p.clearance ?? 'public');

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = widget.dataset;
    final level = levelLabel(d.level);
    // Groups first: sharing with a unit is the common case.
    final candidates = store.principals.values
        .where((p) => p.id != store.user.id)
        .where(
          (p) => _search.isEmpty || p.name.toLowerCase().contains(_search),
        )
        .toList()
      ..sort((a, b) => b.kind.index.compareTo(a.kind.index));
    final canShare = _audience.isNotEmpty && _tags.shareable && _attested;
    final missing = [
      if (_audience.isEmpty) 'pick who gets it',
      if (_keywords.isEmpty) 'add a keyword',
      if (_systems.isEmpty && _affiliations.isEmpty)
        'add a system or affiliation',
      if (!_attested) 'confirm the attestation',
    ];

    Widget section(String title, String? help) => Padding(
          padding: const EdgeInsets.only(
            top: SoliplexSpacing.s4,
            bottom: SoliplexSpacing.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (help != null)
                Text(
                  help,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s6,
            SoliplexSpacing.s6,
            SoliplexSpacing.s6,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share dataset', style: theme.textTheme.titleLarge),
              const SizedBox(height: SoliplexSpacing.s1),
              Row(
                children: [
                  LevelBadge(d.level),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Expanded(child: DatasetLabel(d)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          // Not lazy: short enough to build whole, so every field is there
          // to tab into.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section(
                  'Who gets it',
                  'People and groups. There is no "everyone" — clearance alone '
                      'is not need-to-know.',
                ),
                SoliplexInput(
                  hintText: 'Search people and groups',
                  leadingIcon: const Icon(Icons.search),
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: SoliplexSpacing.s2),
                for (final p in candidates)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _audience.contains(p.id),
                    onChanged: _cleared(p)
                        ? (v) => setState(
                              () => v ?? false
                                  ? _audience.add(p.id)
                                  : _audience.remove(p.id),
                            )
                        : null,
                    secondary: Icon(
                      p.kind == PrincipalKind.group
                          ? Icons.groups_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      _cleared(p)
                          ? [
                              if (p.detail != null) p.detail!,
                              if (p.clearance != null)
                                'cleared ${levelLabel(p.clearance!)}',
                            ].join(' · ')
                          : "Clearance below $level — wouldn't have access",
                    ),
                  ),
                section(
                  'Tags',
                  'Required to share: at least one keyword, and an affiliation '
                      'or a system. They are how others find it in the catalog.',
                ),
                TagField(
                  label: 'Keywords',
                  values: _keywords,
                  suggestions: store.tagSuggestions(Facet.keyword),
                  onChanged: (v) => setState(() => _keywords = v),
                ),
                const SizedBox(height: SoliplexSpacing.s3),
                TagField(
                  label: 'System / equipment',
                  hintText: 'e.g. P-100',
                  values: _systems,
                  suggestions: store.tagSuggestions(Facet.system),
                  onChanged: (v) => setState(() => _systems = v),
                ),
                const SizedBox(height: SoliplexSpacing.s3),
                TagField(
                  label: 'Affiliation (division › site › team)',
                  hintText: 'e.g. Ops › Plant › Maintenance',
                  values: _affiliations,
                  suggestions: store.tagSuggestions(Facet.affiliation),
                  onChanged: (v) => setState(() => _affiliations = v),
                ),
                const SizedBox(height: SoliplexSpacing.s4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _attested,
                  onChanged: (v) => setState(() => _attested = v ?? false),
                  title: Text(
                    'I confirm everyone selected is authorized to receive '
                    'information up to $level and has a need to know.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: const Text(
                    "Soliplex doesn't enforce classification or need-to-know.",
                  ),
                ),
                const SizedBox(height: SoliplexSpacing.s3),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  missing.isEmpty ? '' : 'To share: ${missing.join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              SoliplexButton.text(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                onPressed: canShare
                    ? () {
                        store.share(d, _audience, _tags);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Shared ${d.label} with ${_audience.length} '
                              '${_audience.length == 1 ? 'recipient' : 'recipients'}.',
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.group_add_outlined),
                child: const Text('Share'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Marks a dataset as one not to pick any more. Nothing is deleted.
Future<void> showDeprecateDialog(BuildContext context, Dataset dataset) =>
    _showAdaptiveDialog(
      context,
      (_) => _DeprecateDialog(dataset: dataset),
      width: 520,
    );

class _DeprecateDialog extends StatefulWidget {
  const _DeprecateDialog({required this.dataset});

  final Dataset dataset;

  @override
  State<_DeprecateDialog> createState() => _DeprecateDialogState();
}

class _DeprecateDialogState extends State<_DeprecateDialog> {
  String _reason = '';
  String? _replacedBy;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final d = widget.dataset;
    final candidates = store.visible
        .where((c) => c.id != d.id && !c.isDeprecated)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SoliplexSpacing.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deprecate dataset', style: theme.textTheme.titleLarge),
          const SizedBox(height: SoliplexSpacing.s1),
          DatasetLabel(d),
          const SizedBox(height: SoliplexSpacing.s4),
          const Notice(
            text: "Datasets can't be deleted or versioned. Deprecating hides "
                "it from the catalog and stops it being newly shared; threads "
                'already using it keep working and show a warning.',
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          SoliplexInput(
            label: 'Reason (required)',
            hintText: 'What is wrong or outdated about it?',
            maxLines: 3,
            minLines: 2,
            onChanged: (v) => setState(() => _reason = v.trim()),
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexDropdown<String>(
            label: 'Replaced by (optional)',
            width: 460,
            entries: [
              for (final c in candidates)
                SoliplexDropdownEntry(value: c.id, label: c.label),
            ],
            onSelected: (v) => setState(() => _replacedBy = v),
          ),
          const SizedBox(height: SoliplexSpacing.s6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SoliplexButton.text(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                intent: ButtonIntent.danger,
                onPressed: _reason.isEmpty
                    ? null
                    : () {
                        store.deprecate(
                          d,
                          reason: _reason.endsWith('.') ? _reason : '$_reason.',
                          replacedById: _replacedBy,
                        );
                        Navigator.of(context).pop();
                      },
                child: const Text('Deprecate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showOutdatedDialog(
  BuildContext context,
  Dataset dataset,
  DatasetFile file,
) =>
    _showAdaptiveDialog(
      context,
      (_) => _OutdatedDialog(dataset: dataset, file: file),
      width: 520,
    );

class _OutdatedDialog extends StatefulWidget {
  const _OutdatedDialog({required this.dataset, required this.file});

  final Dataset dataset;
  final DatasetFile file;

  @override
  State<_OutdatedDialog> createState() => _OutdatedDialogState();
}

class _OutdatedDialogState extends State<_OutdatedDialog> {
  String _reason = '';
  String? _replacedBy;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final candidates = [
      for (final f in widget.dataset.files)
        if (f != widget.file && f.outdated == null) f.name,
    ]..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SoliplexSpacing.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mark file outdated', style: theme.textTheme.titleLarge),
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            widget.file.name,
            style: context.monospaceOn(theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          const Notice(
            text: "Files can't be removed from a dataset. Marking one outdated "
                'keeps it indexed and searchable, but everyone sees the mark '
                'and the agent is told when it retrieves from the file. '
                'Anyone with access can clear the mark.',
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          SoliplexInput(
            label: 'Reason (required)',
            hintText: 'What is wrong or outdated about it?',
            maxLines: 3,
            minLines: 2,
            onChanged: (v) => setState(() => _reason = v.trim()),
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexDropdown<String>(
            label: 'Use instead (optional)',
            width: 460,
            entries: [
              for (final name in candidates)
                SoliplexDropdownEntry(value: name, label: name),
            ],
            onSelected: (v) => setState(() => _replacedBy = v),
          ),
          const SizedBox(height: SoliplexSpacing.s6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SoliplexButton.text(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                onPressed: _reason.isEmpty
                    ? null
                    : () {
                        store.markOutdated(
                          widget.dataset,
                          widget.file,
                          reason: _reason.endsWith('.') ? _reason : '$_reason.',
                          replacedBy: _replacedBy,
                        );
                        Navigator.of(context).pop();
                      },
                child: const Text('Mark outdated'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
