import 'package:soliplex_agent/src/host/host_api.dart';

/// In-memory [HostApi] implementation for testing.
///
/// Stores DataFrames and charts in maps, keyed by auto-incrementing
/// handles. The [invoke] method delegates to a configurable handler
/// or throws [UnimplementedError] by default.
class FakeHostApi implements HostApi {
  /// Creates a fake host API.
  ///
  /// Optionally provide an [invokeHandler] to handle [invoke] calls.
  FakeHostApi({this.invokeHandler});

  /// Handler for [invoke] calls. If null, [invoke] throws.
  final Future<Object?> Function(String name, Map<String, Object?> args)?
  invokeHandler;

  final Map<int, Map<String, List<Object?>>> _dataFrames = {};
  final Map<int, Map<String, Object?>> _charts = {};
  int _nextHandle = 1;

  /// All registered DataFrames, keyed by handle.
  Map<int, Map<String, List<Object?>>> get dataFrames =>
      Map.unmodifiable(_dataFrames);

  /// All registered charts, keyed by handle.
  Map<int, Map<String, Object?>> get charts => Map.unmodifiable(_charts);

  @override
  int registerDataFrame(Map<String, List<Object?>> columns) {
    final handle = _nextHandle++;
    _dataFrames[handle] = Map.unmodifiable(columns);
    return handle;
  }

  @override
  Map<String, List<Object?>>? getDataFrame(int handle) => _dataFrames[handle];

  @override
  int registerChart(Map<String, Object?> chartConfig) {
    final handle = _nextHandle++;
    _charts[handle] = Map.unmodifiable(chartConfig);
    return handle;
  }

  @override
  bool updateChart(int chartId, Map<String, Object?> chartConfig) {
    if (!_charts.containsKey(chartId)) return false;
    _charts[chartId] = Map.unmodifiable(chartConfig);
    return true;
  }

  @override
  Future<Object?> invoke(String name, Map<String, Object?> args) async {
    final handler = invokeHandler;
    if (handler == null) {
      throw UnimplementedError('FakeHostApi.invoke: no handler for "$name"');
    }
    return handler(name, args);
  }
}
