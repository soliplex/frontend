import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_manager.dart';

final serverManagerProvider = Provider<ServerManager>(
  (_) => throw UnimplementedError('must be overridden by authModule'),
);
