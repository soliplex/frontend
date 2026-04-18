import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ScriptingState;
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart'
    show RoomEnvironmentRegistry;

import '../../auth/server_entry.dart';
import '../../diagnostics/diagnostics_providers.dart';
import '../../diagnostics/models/http_event_grouper.dart';
import '../../diagnostics/ui/http_event_tile.dart';
import '../../diagnostics/ui/run_http_detail_page.dart';

class DebugConsoleScreen extends ConsumerStatefulWidget {
  const DebugConsoleScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.envRegistry,
    this.pythonExecutor,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final RoomEnvironmentRegistry envRegistry;
  final Future<String> Function(String code)? pythonExecutor;

  @override
  ConsumerState<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends ConsumerState<DebugConsoleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.http, size: 18),
            label: const Text('Network'),
            onPressed: () => context.push('/diagnostics/network'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'REPL'),
            Tab(text: 'Events'),
            Tab(text: 'Sessions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReplTab(executor: widget.pythonExecutor),
          _EventsTab(
            serverId: widget.serverEntry.serverId,
            roomId: widget.roomId,
          ),
          _SessionsTab(
            registry: widget.envRegistry,
            currentServerId: widget.serverEntry.serverId,
            currentRoomId: widget.roomId,
          ),
        ],
      ),
    );
  }
}

// ─── REPL ────────────────────────────────────────────────────────────────────

typedef _HistoryEntry = ({String code, String output, bool isError});

class _ReplTab extends StatefulWidget {
  const _ReplTab({this.executor});

  final Future<String> Function(String code)? executor;

  @override
  State<_ReplTab> createState() => _ReplTabState();
}

class _ReplTabState extends State<_ReplTab> with AutomaticKeepAliveClientMixin {
  final List<_HistoryEntry> _history = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _running = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _running || widget.executor == null) return;
    setState(() => _running = true);
    _controller.clear();
    String output;
    try {
      output = await widget.executor!(code);
    } catch (e) {
      output = 'Error: $e';
    }
    if (!mounted) return;
    setState(() {
      _history.add((
        code: code,
        output: output,
        isError: output.startsWith('Error:'),
      ));
      _running = false;
    });
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 13,
    );

    if (widget.executor == null) {
      return Center(
        child: Text(
          'No Python interpreter — send a message first.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: _history.isEmpty
              ? Center(
                  child: Text(
                    'Type Python code below and press Enter',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  itemBuilder: (_, i) {
                    final e = _history[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '>>> ',
                                style: mono?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(child: Text(e.code, style: mono)),
                            ],
                          ),
                          if (e.output.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 32),
                              child: Text(
                                e.output,
                                style: mono?.copyWith(
                                  color: e.isError ? cs.error : cs.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        _SnippetBar(onSelected: (s) {
          _controller.text = s;
          _focusNode.requestFocus();
        }),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _run,
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: null,
                    style: mono,
                    textInputAction: TextInputAction.newline,
                    readOnly: _running,
                    decoration: InputDecoration(
                      hintText:
                          'notify_show(kind="success", title="Hi", body="")',
                      hintStyle: mono?.copyWith(color: cs.outline),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (_, value, __) => IconButton(
                  icon: _running
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  tooltip: 'Run (Enter)',
                  onPressed:
                      value.text.trim().isEmpty || _running ? null : _run,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Snippet bar ─────────────────────────────────────────────────────────────

typedef _Snippet = ({String label, String code});

const _kSnippets = <_Snippet>[
  (
    label: 'notify',
    code: "notify_show(kind='success', title='Hello', body='from Python')"
  ),
  (label: 'modal', code: "ui_show_modal('Info', 'This is a modal message.')"),
  (label: 'confirm', code: "ui_request_confirm('delete', 'Delete this item?')"),
  (
    label: 'form',
    code:
        "ui_show_form({'key':'prefs','fields':[{'key':'name','label':'Your name','type':'text'}]})"
  ),
  (label: 'list_servers', code: 'soliplex_list_servers()'),
  (label: 'list_rooms', code: "soliplex_list_rooms(server='<id>')"),
  (label: 'help', code: 'help()'),
  (label: '1+1', code: '1 + 1'),
];

class _SnippetBar extends StatelessWidget {
  const _SnippetBar({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _kSnippets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final s = _kSnippets[i];
          return ActionChip(
            label: Text(s.label),
            labelStyle: TextStyle(fontSize: 11, color: cs.primary),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
            onPressed: () => onSelected(s.code),
          );
        },
      ),
    );
  }
}

// ─── Events ──────────────────────────────────────────────────────────────────

class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.serverId, required this.roomId});

  final String serverId;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspector = ref.watch(networkInspectorProvider);
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) {
        final groups = groupHttpEvents(inspector.events).reversed.toList();
        if (groups.isEmpty) {
          return const Center(child: Text('No HTTP events yet.'));
        }
        return ListView.separated(
          itemCount: groups.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final group = groups[i];
            return HttpEventTile(
              group: group,
              dense: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RunHttpDetailPage(groups: [group]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Sessions ────────────────────────────────────────────────────────────────

class _SessionsTab extends StatefulWidget {
  const _SessionsTab({
    required this.registry,
    required this.currentServerId,
    required this.currentRoomId,
  });

  final RoomEnvironmentRegistry registry;
  final String currentServerId;
  final String currentRoomId;

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentKey = '${widget.currentServerId}:${widget.currentRoomId}';
    final envs = widget.registry.environments;
    final platform = kIsWeb ? 'WASM' : 'FFI';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'Python ($platform)',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh',
                onPressed: () => setState(() {}),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (envs.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No active interpreters — send a message first.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: envs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final key = envs.keys.elementAt(i);
                final env = envs.values.elementAt(i);
                final isCurrent = key == currentKey;
                final scriptingState = env.scriptingState.watch(context);
                final isExecuting = scriptingState == ScriptingState.executing;
                final isDisposed = scriptingState == ScriptingState.disposed;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? cs.primaryContainer.withValues(alpha: 0.3)
                        : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: isCurrent
                        ? Border.all(
                            color: cs.primary.withValues(alpha: 0.4),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: isExecuting
                            ? CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: cs.primary,
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDisposed ? cs.outline : cs.primary,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              key,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: isCurrent ? FontWeight.bold : null,
                              ),
                            ),
                            Text(
                              '${scriptingState.name}  ·  $platform',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.outline,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCurrent)
                        Text(
                          'current',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
