import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_client/soliplex_client.dart' hide Room, State;

import '../../auth/server_entry.dart';
import 'room_info/client_tools_card.dart';
import 'room_info/documents_card.dart';
import 'room_info/expandable_list_card.dart';
import 'room_info/features_card.dart';
import 'room_info/quizzes_card.dart';
import 'room_info/room_info_widgets.dart';
import 'room_info/skill_card.dart';
import 'room_info/system_prompt_viewer.dart';

class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.toolRegistryResolver,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final Future<ToolRegistry> Function(String roomId) toolRegistryResolver;

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  late CancelToken _cancelToken;
  late Future<Room> _roomFuture;
  late Future<List<RagDocument>> _documentsFuture;
  late Future<List<Tool>> _clientToolsFuture;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    final api = widget.serverEntry.connection.api;
    _roomFuture = api.getRoom(widget.roomId, cancelToken: _cancelToken);
    _documentsFuture =
        api.getDocuments(widget.roomId, cancelToken: _cancelToken)..ignore();
    _clientToolsFuture = widget
        .toolRegistryResolver(widget.roomId)
        .then((r) => r.toolDefinitions);
  }

  @override
  void dispose() {
    _cancelToken.cancel('disposed');
    super.dispose();
  }

  void _retryDocuments() {
    setState(() {
      _cancelToken.cancel('retry');
      _cancelToken = CancelToken();
      _documentsFuture = widget.serverEntry.connection.api
          .getDocuments(widget.roomId, cancelToken: _cancelToken)
        ..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.adaptive.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(
                '/room/${widget.serverEntry.alias}/${widget.roomId}',
              );
            }
          },
        ),
        title: const Text('Room Information'),
      ),
      body: FutureBuilder<Room>(
        future: _roomFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load room'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Room not found'));
          }
          return _RoomInfoBody(
            room: snapshot.data!,
            serverUrl: widget.serverEntry.serverUrl,
            api: widget.serverEntry.connection.api,
            serverAlias: widget.serverEntry.alias,
            roomId: widget.roomId,
            documentsFuture: _documentsFuture,
            clientToolsFuture: _clientToolsFuture,
            onRetryDocuments: _retryDocuments,
          );
        },
      ),
    );
  }
}

class _RoomInfoBody extends StatelessWidget {
  const _RoomInfoBody({
    required this.room,
    required this.serverUrl,
    required this.api,
    required this.serverAlias,
    required this.roomId,
    required this.documentsFuture,
    required this.clientToolsFuture,
    required this.onRetryDocuments,
  });

  final Room room;
  final Uri serverUrl;
  final SoliplexApi api;
  final String serverAlias;
  final String roomId;
  final Future<List<RagDocument>> documentsFuture;
  final Future<List<Tool>> clientToolsFuture;
  final VoidCallback onRetryDocuments;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  formatServerUrl(serverUrl),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  room.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (room.hasDescription)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                room.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          _AgentCard(agent: room.agent),
          FeaturesCard(room: room, api: api, roomId: roomId),
          QuizzesCard(
            quizzes: room.quizzes,
            onQuizTapped: (quizId) {
              final from = Uri.encodeComponent(
                '/room/$serverAlias/$roomId/info',
              );
              context.go(
                '/room/$serverAlias/$roomId/quiz/$quizId?from=$from',
              );
            },
          ),
          ExpandableListCard<MapEntry<String, RoomSkill>>(
            key: const ValueKey('skills'),
            title: 'SKILLS',
            items: room.skills.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => buildSkillContent(e.value),
          ),
          ExpandableListCard<MapEntry<String, RoomTool>>(
            key: const ValueKey('tools'),
            title: 'TOOLS',
            items: room.tools.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => _buildToolContent(e.value),
          ),
          ExpandableListCard<MapEntry<String, McpClientToolset>>(
            key: const ValueKey('mcp-toolsets'),
            title: 'MCP CLIENT TOOLSETS',
            emptyLabel: 'MCP client toolsets',
            items: room.mcpClientToolsets.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => _buildToolsetContent(e.value),
          ),
          ClientToolsCard(clientToolsFuture: clientToolsFuture),
          DocumentsCard(
            documentsFuture: documentsFuture,
            onRetry: onRetryDocuments,
          ),
        ],
      ),
    );
  }
}

Widget _buildToolContent(RoomTool tool) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoRow(label: 'Kind', value: tool.kind),
      if (tool.description.isNotEmpty)
        InfoRow(label: 'Description', value: tool.description),
      if (tool.allowMcp) const InfoRow(label: 'Allow MCP', value: 'Yes'),
      if (tool.toolRequires.isNotEmpty)
        InfoRow(label: 'Requires', value: tool.toolRequires),
      if (tool.aguiFeatureNames.isNotEmpty)
        InfoRow(
          label: 'AG-UI Features',
          value: tool.aguiFeatureNames.join(', '),
        ),
    ],
  );
}

Widget _buildToolsetContent(McpClientToolset toolset) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoRow(label: 'Kind', value: toolset.kind),
      if (toolset.allowedTools != null)
        InfoRow(
          label: 'Allowed Tools',
          value: toolset.allowedTools!.join(', '),
        ),
    ],
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final RoomAgent? agent;

  @override
  Widget build(BuildContext context) {
    final agent = this.agent;
    if (agent == null) {
      return const SectionCard(
        title: 'AGENT',
        children: [EmptyMessage(label: 'agent')],
      );
    }
    return SectionCard(
      title: 'AGENT',
      children: [
        InfoRow(label: 'Model', value: agent.displayModelName),
        ...switch (agent) {
          DefaultRoomAgent(
            :final providerType,
            :final retries,
            :final systemPrompt,
          ) =>
            [
              InfoRow(label: 'Provider', value: providerType),
              InfoRow(label: 'Retries', value: '$retries'),
              if (systemPrompt != null)
                SystemPromptViewer(prompt: systemPrompt),
            ],
          FactoryRoomAgent(:final extraConfig) when extraConfig.isNotEmpty => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extra Config',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    formatDynamicValue(
                      extraConfig,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          _ => <Widget>[],
        },
        if (agent.aguiFeatureNames.isNotEmpty)
          InfoRow(
            label: 'AG-UI Features',
            value: agent.aguiFeatureNames.join(', '),
          ),
      ],
    );
  }
}
