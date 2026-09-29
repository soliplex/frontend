import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_state_warning.dart';

/// The warnings a replayed [state]'s citations raise for the answers rendered
/// from it.
Set<ThreadStateWarning> citationStateWarnings(Map<String, dynamic> state) => {
      if (RagSnapshot.carriesNonIdCitations(state))
        ThreadStateWarning.legacyCitations,
    };

/// The warnings a send from [history]'s current state gives rise to: the
/// cached state is what the next run is seeded from.
Set<ThreadStateWarning> outgoingStateWarnings(ThreadHistory history) => {
      if (RagSnapshot.carriesNonIdCitations(history.aguiState))
        ThreadStateWarning.legacyCitations,
    };

/// The warnings a thread opened with [history] shows.
Set<ThreadStateWarning> threadStateWarnings(ThreadHistory history) => {
      ...history.storedStateWarnings,
      ...outgoingStateWarnings(history),
    };
