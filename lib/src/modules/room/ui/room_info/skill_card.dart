import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'room_info_widgets.dart';
import 'package:soliplex_design/soliplex_design.dart';

Widget buildSkillContent(RoomSkill skill) {
  return SkillContentColumn(skill: skill);
}

/// The skill kinds whose `extra_parameters` have a key space fixed by backend
/// code, and so the only ones safe to display.
///
/// The test is the keys, not the values: a `native` skill's values are the
/// operator's (`database_names` is what they wrote under `name:`), but the
/// key set is one the backend chose, and a name is not a credential. An
/// `entrypoint` skill's keys are its whole YAML block minus `kind`, `name`
/// and `defer_loading`, splatted into a third-party
/// `create_capability(**params)` — the operator names the keys, so one can be
/// `api_key`, nothing interpolates or bounds them, and this screen is in
/// front of everyone who opens the room. A kind not named here is withheld
/// for the same reason.
const _kindsWithBoundedParameters = {'filesystem', 'native'};

Map<String, dynamic> _displayableParameters(RoomSkill skill) =>
    _kindsWithBoundedParameters.contains(skill.source)
        ? skill.extraParameters
        : const {};

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
        if (_displayableParameters(skill).isNotEmpty ||
            skill.stateTypeSchema.isNotEmpty)
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
        ('Extra Parameters', _displayableParameters(skill)),
        ('State Schema', skill.stateTypeSchema),
      ],
    );
  }
}
