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
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    final noneStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    Widget field(String label, String? value) {
      final isNone = value == null || value.isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 2),
          Text(
            isNone ? 'None' : value,
            style: isNone ? noneStyle : valueStyle,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field('description', skill.description),
        const SizedBox(height: 8),
        field('source', skill.source),
        const SizedBox(height: 8),
        field('license', skill.license),
        const SizedBox(height: 8),
        field('compatibility', skill.compatibility),
        const SizedBox(height: 8),
        field('allowed_tools', skill.allowedTools?.join(', ')),
        const SizedBox(height: 8),
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
      fontWeight: FontWeight.w600,
    );
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    final noneStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    Widget mapSection(String title, Map<String, dynamic>? data) {
      final isEmpty = data == null || data.isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: sectionStyle),
          const SizedBox(height: 8),
          if (isEmpty)
            Text('Empty', style: noneStyle)
          else
            for (final entry in data.entries) ...[
              SizedBox(
                width: double.infinity,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key, style: labelStyle),
                        const SizedBox(height: 2),
                        formatDynamicValue(
                          entry.value,
                          style: valueStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      );
    }

    return AlertDialog(
      title: Text(
        skill.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              mapSection('Metadata', skill.metadata),
              const SizedBox(height: 16),
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
