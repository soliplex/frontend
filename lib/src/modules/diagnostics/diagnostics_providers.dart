import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_inspector.dart';

final networkInspectorProvider = Provider<NetworkInspector>(
  (_) => throw UnimplementedError('must be overridden by diagnosticsModule'),
);
