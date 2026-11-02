import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../core/app_identity.dart';
import '../../core/routes.dart';
import '../../core/status_message_config.dart';
import '../../stores/document_selections.dart';
import '../../modules/room/message_expansions.dart';
import '../../modules/room/room_providers.dart';
import '../chat/chat_screen.dart';
import '../chat/static_backend.dart';
import 'model.dart';
import 'sample_data.dart';
import 'store.dart';
import 'ui/common.dart';
import 'ui/create_dataset_screen.dart';
import 'ui/dataset_detail_screen.dart';
import 'ui/lobby_screen.dart';
import 'ui/thread_datasets.dart';
import 'ui/upload_screen.dart';

/// Rooms as presets, datasets as a catalog: the lobby, the dataset pages and
/// the chat, on a static backend.
///
/// Everything a dataset is lives in a [DatasetsStore] above the router — the
/// backend has no dataset entity yet, so nothing here is on the wire.
class DatasetsMockup extends StatefulWidget {
  const DatasetsMockup({super.key});

  @override
  State<DatasetsMockup> createState() => _DatasetsMockupState();
}

class _DatasetsMockupState extends State<DatasetsMockup> {
  late final StaticBackend _backend;
  late final DatasetsStore _store;
  late final GoRouter _router;
  final _documentSelections = DocumentSelections();

  @override
  void initState() {
    super.initState();
    _backend = StaticBackend(api: datasetsApi());
    _store = sampleStore();
    final seam = threadDatasetsSeam(_store);
    _router = GoRouter(
      // `--dart-define=DATASETS_ROUTE=/datasets/ops/pump-service-manuals` opens
      // straight on a screen — and again after every hot restart.
      initialLocation: const String.fromEnvironment(
        'DATASETS_ROUTE',
        defaultValue: AppRoutes.lobby,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.lobby,
          pageBuilder: (context, state) => NoTransitionPage(
            child: DatasetsLobbyScreen(
              entry: _backend.entry,
              view: LobbyView.parse(state.uri.queryParameters['view']),
            ),
          ),
        ),
        GoRoute(
          path: '/datasets/new',
          builder: (context, state) => const CreateDatasetScreen(),
        ),
        GoRoute(
          path: '/datasets/:namespace/:slug',
          builder: (context, state) => DatasetDetailScreen(
            datasetId: _datasetId(state),
          ),
        ),
        GoRoute(
          path: '/datasets/:namespace/:slug/upload',
          builder: (context, state) =>
              UploadScreen(datasetId: _datasetId(state)),
        ),
        for (final path in const [
          '/room/:serverAlias/:roomId',
          '/room/:serverAlias/:roomId/thread/:threadId',
          // Conversations outside rooms: the hidden room, on a page of its
          // own with no room rail.
          '/conversations',
          '/conversations/thread/:threadId',
        ])
          GoRoute(
            path: path,
            pageBuilder: (context, state) {
              final roomId =
                  state.pathParameters['roomId'] ?? conversationsRoomId;
              final threadId = state.pathParameters['threadId'];
              return NoTransitionPage(
                // A room's band shows its ceiling; outside any room, the
                // level follows the datasets the conversation uses.
                child: ListenableBuilder(
                  listenable: _store,
                  builder: (context, child) => CeilingScope(
                    level: _store.levelOf(roomId, threadId),
                    child: child!,
                  ),
                  child: RoomScreen(
                    serverEntry: _backend.entry,
                    roomId: roomId,
                    threadId: threadId,
                    appName: AppIdentity.soliplex.appName,
                    runtimeManager: _backend.runtimeManager,
                    registry: _backend.registry,
                    uploadRegistry: _backend.uploadRegistry,
                    documentSelections: _documentSelections,
                    datasets: seam,
                    conversationsRoomId: conversationsRoomId,
                    conversationsLocation: conversationsLocation,
                    startNew: state.uri.queryParameters.containsKey('new'),
                  ),
                ),
              );
            },
          ),
        for (final (path, label) in const [
          ('/room/:serverAlias/:roomId/info', 'Room info'),
          ('/room/:serverAlias/:roomId/quiz/:quizId', 'Quiz'),
          (AppRoutes.diagnostics, 'Diagnostics'),
          (AppRoutes.versions, 'Versions'),
          (AppRoutes.home, 'Home'),
        ])
          GoRoute(
            path: path,
            builder: (context, state) => _Placeholder(label: label),
          ),
      ],
    );
  }

  static String _datasetId(GoRouterState state) =>
      '${state.pathParameters['namespace']}/${state.pathParameters['slug']}';

  @override
  void dispose() {
    _router.dispose();
    _store.dispose();
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
      child: DatasetsScope(
        store: _store,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

/// Stands in for a screen outside the mockup's scope.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});

  final String label;

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
              'Not part of the datasets mockup',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s4),
            SoliplexButton.text(
              onPressed: () => context.go(AppRoutes.lobby),
              icon: const Icon(Icons.arrow_back),
              child: const Text('Back to the lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
