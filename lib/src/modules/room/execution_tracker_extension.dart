import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';
import 'execution_bands.dart';

/// A [SessionExtension] that builds the session's execution bands from its
/// runs' fold, with the [ExecutionBands] a reload builds them with.
///
/// Observes the session's run fold from [onAttach] until [onDispose]. The
/// resulting [Map<String, ExecutionTracker>] is exposed via the [stateSignal]
/// and the convenience [trackers] getter.
///
/// [ThreadViewState] absorbs the live trackers into its own historical
/// registry on detach, so execution data persists after the session ends.
class ExecutionTrackerExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, ExecutionTracker>>
    implements RunFoldObserver {
  ExecutionTrackerExtension({required Logger logger}) : _logger = logger {
    setInitialState(const <String, ExecutionTracker>{});
  }

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

  /// Current tracker map (historical + live for this session).
  Map<String, ExecutionTracker> get trackers => _bands?.trackers ?? const {};

  /// Every run of the session's turn that has started.
  Set<String> get runs => _bands?.runs ?? const {};

  @override
  Future<void> onAttach(AgentSession session) async {
    _bands = ExecutionBands.live(logger: _logger);
    _stopObserving = session.observeRunFold(this);
  }

  @override
  void onDispose() {
    _stopObserving?.call();
    _stopObserving = null;
    _bands?.finish();
    _bands = null;
    super.onDispose();
  }

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) {
    _bands!.runStarted(fold, continuesTurn: continuesTurn);
    _sync();
  }

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) {
    _bands!.eventFolded(fold, processed: processed);
    _sync();
  }

  @override
  void runEnded(RunEnding ending) {
    _bands!.runEnded(ending);
    _sync();
  }

  void _sync() => state = trackers;
}
