import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/source_reference.dart';

/// State associated with a user message and its response.
///
/// Keyed by user message ID, this captures the source references (citations)
/// that were retrieved during the assistant's response to that message,
/// and the run ID needed for feedback submission.
@immutable
class MessageState {
  /// Creates a message state.
  MessageState({
    required this.userMessageId,
    required List<SourceReference> sourceReferences,
    this.runId,
  }) : sourceReferences = List.unmodifiable(sourceReferences);

  /// The ID of the user message this state is associated with.
  final String userMessageId;

  /// Source references (citations) retrieved for the assistant's response.
  final List<SourceReference> sourceReferences;

  /// The run ID that produced the assistant's response.
  ///
  /// Used to submit feedback via the feedback endpoint. Null when the run ID
  /// is not available (e.g., legacy history without run tracking).
  final String? runId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MessageState) return false;
    const listEquals = ListEquality<SourceReference>();
    return userMessageId == other.userMessageId &&
        listEquals.equals(sourceReferences, other.sourceReferences) &&
        runId == other.runId;
  }

  @override
  int get hashCode => Object.hash(
    userMessageId,
    const ListEquality<SourceReference>().hash(sourceReferences),
    runId,
  );

  @override
  String toString() =>
      'MessageState('
      'userMessageId: $userMessageId, '
      'sourceReferences: ${sourceReferences.length}, '
      'runId: $runId)';
}
