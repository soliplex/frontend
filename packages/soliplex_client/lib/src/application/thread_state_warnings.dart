import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_state_warning.dart';

/// The warnings a replayed [state]'s citations raise for the answers rendered
/// from it.
Set<ThreadStateWarning> citationStateWarnings(Map<String, dynamic> state) => {
      if (RagSnapshot.carriesNonIdCitations(state))
        ThreadStateWarning.legacyCitations,
    };

/// The warnings a send from [history] gives rise to. Citations are judged on
/// the cached state, which is what the next run is seeded from. The saved
/// search scope keeps the verdict the loaded history's run-input readers
/// reached ([ThreadHistory.storedStateWarnings]): the replayed state can be an
/// older run's. A history captured from a finished run carries no scope
/// verdict. Whether the state is incomplete is the history's own
/// [ThreadHistory.aguiStateIncomplete], which a captured history carries too.
Set<ThreadStateWarning> outgoingStateWarnings(ThreadHistory history) => {
      if (RagSnapshot.carriesNonIdCitations(history.aguiState))
        ThreadStateWarning.legacyCitations,
      if (history.storedStateWarnings
          .contains(ThreadStateWarning.scopeUnreadable))
        ThreadStateWarning.scopeUnreadable,
      if (history.aguiStateIncomplete) ThreadStateWarning.stateIncomplete,
    };

/// The warnings a thread opened with [history] shows. Its saved search scope
/// is judged by [ThreadHistory.storedStateWarnings] alone: the selection UI
/// reads the scope from the newest run's input, and the replayed state can
/// be an older run's.
Set<ThreadStateWarning> threadStateWarnings(ThreadHistory history) => {
      ...history.storedStateWarnings,
      ...citationStateWarnings(history.aguiState),
      if (history.aguiStateIncomplete) ThreadStateWarning.stateIncomplete,
    };
