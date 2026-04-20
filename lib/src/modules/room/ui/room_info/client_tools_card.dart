import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'expandable_list_card.dart';
import 'room_info_widgets.dart';

class ClientToolsCard extends StatelessWidget {
  const ClientToolsCard({super.key, required this.clientToolsFuture});
  final Future<List<Tool>> clientToolsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Tool>>(
      future: clientToolsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SectionCard(
            title: 'CLIENT TOOLS',
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return const SectionCard(
            title: 'CLIENT TOOLS',
            children: [EmptyMessage(label: 'client tools')],
          );
        }
        final tools = snapshot.data ?? const [];
        if (tools.isEmpty) {
          return SectionCard(
            title: 'CLIENT TOOLS (${tools.length})',
            children: const [EmptyMessage(label: 'client tools')],
          );
        }
        return ExpandableListCard<Tool>(
          key: const ValueKey('client-tools'),
          title: 'CLIENT TOOLS',
          items: tools,
          nameOf: (t) => t.name,
          contentOf:
              (t) => t.description.isNotEmpty ? Text(t.description) : null,
        );
      },
    );
  }
}
