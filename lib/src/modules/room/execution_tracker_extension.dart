import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_bands.dart';
import 'execution_tracker.dart';

/// A [SessionExtension] that builds the session's execution bands from its
/// runs' fold, with the [ExecutionBands] a reload builds them with.
///
/// Observes the session's run fold from [onAttach] until [onDispose]. The
/// bands it builds are exposed via [trackers].
///
/// [ThreadViewState] absorbs the live trackers into its historical trackers
/// on detach, so execution data persists after the session ends.
class ExecutionTrackerExtension extends SessionExtension {
  ExecutionTrackerExtension({required Logger logger}) : _logger = logger;

  final Logger _logger;

  /// Built on attach, for the session whose fold it observes; null before,
  /// and after dispose.
  ExecutionBands? _bands;
  void Function()? _stopObserving;

  @override
  String get namespace => 'execution_tracker';

  @override
  int get priority => 10;

  @override
  List<ClientTool> get tools => const [];

  /// Every band this session's runs have built.
  Map<String, ExecutionTracker> get trackers => _bands?.trackers ?? const {};

  /// Every run of the session's turn that has started.
  Set<String> get runs => _bands?.runs ?? const {};

  @override
  Future<void> onAttach(AgentSession session) async {
    final bands = _bands = ExecutionBands.live(logger: _logger);
    _stopObserving = session.observeRunFold(bands);
  }

  @override
  void onDispose() {
    _stopObserving?.call();
    _stopObserving = null;
    _bands?.finish();
    _bands = null;
  }
}
