import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'room_info_widgets.dart';

Widget buildSkillContent(RoomSkill skill) {
  return SkillContentColumn(skill: skill);
}

class SkillContentColumn extends StatelessWidget {
  const SkillContentColumn({super.key, required this.skill});
  final RoomSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: .w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    final noneStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: .italic,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    Widget field(String label, String? value) {
      final isNone = value == null || value.isEmpty;
      return Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Text(label, style: labelStyle),
          Text(isNone ? 'None' : value, style: isNone ? noneStyle : valueStyle),
        ],
      );
    }

    return Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        field('description', skill.description),
        field('source', skill.source),
        field('license', skill.license),
        field('compatibility', skill.compatibility),
        field('allowed_tools', skill.allowedTools?.join(', ')),
        field('state_namespace', skill.stateNamespace),
        if (skill.metadata.isNotEmpty ||
            (skill.stateTypeSchema?.isNotEmpty ?? false))
          DialogButton(
            label: 'Show more',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SkillDetailDialog(skill: skill),
            ),
          ),
      ],
    );
  }
}

class SkillDetailDialog extends StatelessWidget {
  const SkillDetailDialog({super.key, required this.skill});
  final RoomSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sectionStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: .w600,
    );
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: .w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    final noneStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: .italic,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    Widget mapSection(String title, Map<String, dynamic>? data) {
      final isEmpty = data == null || data.isEmpty;
      return Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Text(title, style: sectionStyle),
          if (isEmpty)
            Text('Empty', style: noneStyle)
          else
            for (final entry in data.entries)
              SizedBox(
                width: .infinity,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const .all(12),
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(entry.key, style: labelStyle),
                        formatDynamicValue(entry.value, style: valueStyle),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      );
    }

    return AlertDialog(
      title: Text(skill.name, overflow: .ellipsis, maxLines: 1),
      content: SizedBox(
        width: .maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 16,
            children: [
              mapSection('Metadata', skill.metadata),
              mapSection('State Schema', skill.stateTypeSchema),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
