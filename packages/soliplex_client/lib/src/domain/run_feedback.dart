import 'package:meta/meta.dart';

/// The feedback record on file for a run.
///
/// At most one exists per run: submitting replaces any earlier record. The
/// record's existence is the point — an absent record is an absent
/// [RunFeedback], which a bare reason string could not express.
@immutable
class RunFeedback {
  /// Creates a run feedback record.
  const RunFeedback({this.reason});

  /// The free-text reason on file, or null when the record carries none.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RunFeedback && reason == other.reason;

  @override
  int get hashCode => reason.hashCode;

  /// Deliberately omits [reason]: it is free text the user or the backend
  /// supplied, and this renders into the exportable diagnostics buffer.
  @override
  String toString() =>
      'RunFeedback(reason: ${reason == null ? 'none' : 'set'})';
}
