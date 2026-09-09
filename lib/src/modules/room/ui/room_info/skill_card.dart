import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'room_info_widgets.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
          const SizedBox(height: SoliplexSpacing.s1),
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
        const SizedBox(height: SoliplexSpacing.s2),
        field('source', skill.source),
        const SizedBox(height: SoliplexSpacing.s2),
        field('state_namespace', skill.stateNamespace),
        if (skill.extraParameters.isNotEmpty ||
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
    return RawParametersDialog(
      title: skill.name,
      sections: [
        ('Extra Parameters', skill.extraParameters),
        ('State Schema', skill.stateTypeSchema),
      ],
    );
  }
}
