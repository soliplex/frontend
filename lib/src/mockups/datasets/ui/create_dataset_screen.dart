import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../core/layout.dart';
import '../classification_levels.dart';
import '../model.dart';
import '../store.dart';
import 'common.dart';
import 'share_dialogs.dart';

/// Creates an empty, private dataset. Its level is the one decision that
/// can't be taken back, so it is asked for plainly and explained.
class CreateDatasetScreen extends StatefulWidget {
  const CreateDatasetScreen({super.key});

  @override
  State<CreateDatasetScreen> createState() => _CreateDatasetScreenState();
}

class _CreateDatasetScreenState extends State<CreateDatasetScreen> {
  String? _namespace;
  String _name = '';
  String _title = '';
  String _description = '';
  String? _level;
  bool _showTags = false;
  Set<String> _keywords = {};
  Set<String> _systems = {};
  Set<String> _affiliations = {};

  static String slugify(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final namespace = _namespace ?? store.user.personalNamespace;
    final slug = slugify(_name);
    final taken = slug.isNotEmpty && store.labelTaken(namespace, slug);
    final ready =
        slug.isNotEmpty && !taken && _title.trim().isNotEmpty && _level != null;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    void create() {
      final d = store.create(
        namespace: namespace,
        slug: slug,
        title: _title.trim(),
        description: _description.trim(),
        level: _level!,
        tags: DatasetTags(
          keywords: _keywords,
          systems: _systems,
          affiliations: _affiliations,
        ),
      );
      context.go('/datasets/${d.id}');
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to the catalog',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/lobby?view=datasets'),
        ),
        title: const Text('New dataset'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: formColumnMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(SoliplexSpacing.s4),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final namespaceField = SoliplexDropdown<String>(
                    label: 'Namespace',
                    width: constraints.maxWidth < SoliplexBreakpoints.mobile
                        ? constraints.maxWidth
                        : 200,
                    initialValue: namespace,
                    entries: [
                      for (final ns in store.namespaces)
                        SoliplexDropdownEntry(
                          value: ns,
                          label: ns == store.user.personalNamespace
                              ? '$ns (personal)'
                              : ns,
                        ),
                    ],
                    onSelected: (v) => setState(() => _namespace = v),
                  );
                  final nameField = SoliplexInput(
                    label: 'Name',
                    hintText: 'pump-notes',
                    errorText: taken
                        ? 'You already have a dataset by that name'
                        : null,
                    onChanged: (v) => setState(() => _name = v),
                  );
                  if (constraints.maxWidth < 440) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        namespaceField,
                        const SizedBox(height: SoliplexSpacing.s3),
                        nameField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      namespaceField,
                      const SizedBox(width: SoliplexSpacing.s3),
                      Expanded(child: nameField),
                    ],
                  );
                },
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              Text.rich(
                TextSpan(
                  text: 'Label: ',
                  children: [
                    TextSpan(
                      text: '$namespace/${slug.isEmpty ? '…' : slug}',
                      style: context.monospaceOn(muted),
                    ),
                  ],
                ),
                style: muted,
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexInput(
                label: 'Title',
                hintText: 'Pump notes',
                onChanged: (v) => setState(() => _title = v),
              ),
              const SizedBox(height: SoliplexSpacing.s3),
              SoliplexInput(
                label: 'Description',
                maxLines: 3,
                minLines: 2,
                onChanged: (v) => setState(() => _description = v),
              ),
              const SizedBox(height: SoliplexSpacing.s6),
              Text('Information level', style: theme.textTheme.titleSmall),
              Text(
                'The highest level of information this dataset may ever '
                "hold. Files declared above it are rejected. This can't be "
                'changed later.',
                style: muted,
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              RadioGroup<String>(
                groupValue: _level,
                onChanged: (v) => setState(() => _level = v),
                child: Column(
                  children: [
                    for (final id in levelIds)
                      RadioListTile<String>(
                        value: id,
                        enabled: isWithin(id, store.user.clearance),
                        contentPadding: EdgeInsets.zero,
                        title: Align(
                          alignment: Alignment.centerLeft,
                          child: LevelBadge(id),
                        ),
                        subtitle: isWithin(id, store.user.clearance)
                            ? null
                            : const Text('Above your clearance'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexButton.text(
                onPressed: () => setState(() => _showTags = !_showTags),
                icon: Icon(_showTags ? Icons.expand_less : Icons.expand_more),
                child: const Text('Tags (optional)'),
              ),
              if (_showTags) ...[
                Text(
                  'Required before you can share: keywords, plus an '
                  'affiliation or a system.',
                  style: muted,
                ),
                const SizedBox(height: SoliplexSpacing.s3),
                TagField(
                  label: 'Keywords',
                  values: _keywords,
                  suggestions: store.tagSuggestions(Facet.keyword),
                  onChanged: (v) => setState(() => _keywords = v),
                ),
                const SizedBox(height: SoliplexSpacing.s3),
                TagField(
                  label: 'System / equipment',
                  values: _systems,
                  suggestions: store.tagSuggestions(Facet.system),
                  onChanged: (v) => setState(() => _systems = v),
                ),
                const SizedBox(height: SoliplexSpacing.s3),
                TagField(
                  label: 'Affiliation',
                  values: _affiliations,
                  suggestions: store.tagSuggestions(Facet.affiliation),
                  onChanged: (v) => setState(() => _affiliations = v),
                ),
              ],
              const SizedBox(height: SoliplexSpacing.s4),
              const Notice(
                warning: true,
                icon: Icons.policy_outlined,
                text: 'Soliplex does not check classification. You are '
                    'responsible for what you put in this dataset.',
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              Align(
                alignment: Alignment.centerRight,
                child: SoliplexButton.filled(
                  onPressed: ready ? create : null,
                  child: const Text('Create dataset'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
