import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/app_identity.dart';
import '../../core/routes.dart';
import '../../core/status_message_config.dart';
import '../../modules/room/document_selections.dart';
import '../../modules/room/message_expansions.dart';
import '../../modules/room/room_providers.dart';
import 'chat_screen.dart';
import 'sample_data.dart';
import 'static_backend.dart';

/// The chat screen on a static backend.
///
/// Runs its own [GoRouter] because the screen navigates by path — between
/// threads, to the room list, to the room's info page — and the room routes
/// are the app's own. Destinations outside the chat get a placeholder page.
class ChatMockup extends StatefulWidget {
  const ChatMockup({super.key});

  @override
  State<ChatMockup> createState() => _ChatMockupState();
}

class _ChatMockupState extends State<ChatMockup> {
  late final StaticBackend _backend;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _backend = StaticBackend(api: sampleApi());
    final alias = _backend.entry.alias;
    _router = GoRouter(
      initialLocation: AppRoutes.thread(alias, 'research', 'retrieval'),
      routes: [
        for (final path in const [
          '/room/:serverAlias/:roomId',
          '/room/:serverAlias/:roomId/thread/:threadId',
        ])
          GoRoute(
            path: path,
            pageBuilder: (context, state) => NoTransitionPage(
              child: RoomScreen(
                serverEntry: _backend.entry,
                roomId: state.pathParameters['roomId']!,
                threadId: state.pathParameters['threadId'],
                appName: AppIdentity.soliplex.appName,
                runtimeManager: _backend.runtimeManager,
                registry: _backend.registry,
                uploadRegistry: _backend.uploadRegistry,
                enableDocumentFilter: true,
                documentSelections: _documentSelections,
              ),
            ),
          ),
        for (final (path, label) in const [
          ('/room/:serverAlias/:roomId/info', 'Room info'),
          ('/room/:serverAlias/:roomId/quiz/:quizId', 'Quiz'),
          (AppRoutes.lobby, 'Lobby'),
          (AppRoutes.diagnostics, 'Diagnostics'),
          (AppRoutes.versions, 'Versions'),
          (AppRoutes.home, 'Home'),
        ])
          GoRoute(
            path: path,
            builder: (context, state) => _Placeholder(
              label: label,
              onBack: () => context.go(
                AppRoutes.thread(alias, 'research', 'retrieval'),
              ),
            ),
          ),
      ],
    );
  }

  final _documentSelections = DocumentSelections();

  @override
  void dispose() {
    _router.dispose();
    _backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
        statusMessageConfigProvider
            .overrideWithValue(StatusMessageConfig.disabled),
      ],
      child: Router.withConfig(config: _router),
    );
  }
}

/// Stands in for a screen outside the chat mockup's scope.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.titleLarge),
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              'Not part of the chat mockup',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s4),
            SoliplexButton.text(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              child: const Text('Back to the chat'),
            ),
          ],
        ),
      ),
    );
  }
}
