import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bus_inspector.dart';
import 'network_inspector.dart';

final networkInspectorProvider = Provider<NetworkInspector>(
  (_) => throw UnimplementedError('must be overridden by diagnosticsModule'),
);

final busInspectorProvider = Provider<BusInspector>(
  (_) => throw UnimplementedError('must be overridden by diagnosticsModule'),
);
