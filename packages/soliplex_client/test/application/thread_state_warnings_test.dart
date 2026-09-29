import 'package:soliplex_client/src/application/thread_state_warnings.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_state_warning.dart';
import 'package:test/test.dart';

ThreadHistory _history(Map<String, dynamic> state) =>
    ThreadHistory(messages: const [], aguiState: state);

void main() {
  group('outgoingStateWarnings', () {
    test('object citations are a legacy-citations warning', () {
      final warnings = outgoingStateWarnings(
        _history({
          'rag': <String, dynamic>{
            'citations': [
              {'document_id': 'doc-1', 'chunk_id': 'chunk-1', 'content': 'x'},
            ],
          },
        }),
      );

      expect(warnings, {ThreadStateWarning.legacyCitations});
    });

    test('a null citations value is a legacy-citations warning', () {
      expect(
        outgoingStateWarnings(
          _history({
            'rag': <String, dynamic>{'citations': null},
          }),
        ),
        {ThreadStateWarning.legacyCitations},
      );
    });

    test('well-formed state gives no warning', () {
      expect(
        outgoingStateWarnings(
          _history({
            'rag': <String, dynamic>{
              'citations': ['chunk-1'],
              'citation_index': <String, dynamic>{},
              'document_filter': null,
            },
            'citation_policy': <String, dynamic>{
              'violations': [1],
            },
            'soliplex-agui-run-feedback': <String, dynamic>{},
          }),
        ),
        isEmpty,
      );
    });

    test('a history loaded with an unreadable scope is scope-unreadable', () {
      expect(
        outgoingStateWarnings(
          ThreadHistory(
            messages: const [],
            storedStateWarnings: const {ThreadStateWarning.scopeUnreadable},
          ),
        ),
        {ThreadStateWarning.scopeUnreadable},
      );
    });

    test('an unreadable scope in the cached state alone gives no warning', () {
      // The replayed state can be an older run's snapshot, so the scope is
      // judged by the verdict the loaded history's run-input readers reached.
      expect(
        outgoingStateWarnings(
          _history({
            'rag': <String, dynamic>{'document_filter': 42},
          }),
        ),
        isEmpty,
      );
    });

    test('an incomplete state is a state-incomplete warning', () {
      expect(
        outgoingStateWarnings(
          ThreadHistory(messages: const [], aguiStateIncomplete: true),
        ),
        {ThreadStateWarning.stateIncomplete},
      );
    });
  });

  group('threadStateWarnings', () {
    test('a thread opened with an incomplete state shows state-incomplete', () {
      expect(
        threadStateWarnings(
          ThreadHistory(messages: const [], aguiStateIncomplete: true),
        ),
        {ThreadStateWarning.stateIncomplete},
      );
    });
  });
}
