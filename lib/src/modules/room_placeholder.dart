import 'package:go_router/go_router.dart';

import '../core/shell_config.dart';
import 'lobby/ui/room_placeholder_screen.dart';

// TODO: Replace with a real room module. The serverId is url.origin
// (e.g. http://localhost:8000) which requires URI encoding in the path.
// Introduce server aliases (short, path-safe IDs) when building the real module.
ModuleContribution roomPlaceholder() {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverId/:roomId',
        pageBuilder: (_, state) => NoTransitionPage(
          child: RoomPlaceholderScreen(
            serverId: state.pathParameters['serverId']!,
            roomId: state.pathParameters['roomId']!,
          ),
        ),
      ),
    ],
  );
}
