// Temporary placeholder — remove when a real lobby module is created.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/shell_config.dart';

ModuleContribution lobbyPlaceholder() {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/lobby',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: LobbyPlaceholderScreen(),
        ),
      ),
    ],
  );
}

class LobbyPlaceholderScreen extends StatelessWidget {
  const LobbyPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => GoRouter.of(context).go('/'),
        ),
      ),
      body: const Center(
        child: Text('Lobby — coming soon'),
      ),
    );
  }
}
