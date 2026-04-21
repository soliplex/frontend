import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A persisted AG-UI activity snapshot.
///
/// One record per `ActivitySnapshotEvent` the backend emits. The raw
/// `content` payload is stored as-is; consumers decode the fields they
/// need (e.g. `skill_tool_call` activities store a double-encoded
/// `args` string under `content['args']`).
@immutable
class ActivityRecord {
  /// Creates an activity record.
  const ActivityRecord({
    required this.messageId,
    required this.activityType,
    required this.content,
    required this.timestamp,
  });

  /// Identifier for the target `ActivityMessage`. Snapshots with the
  /// same [messageId] update the same record.
  final String messageId;

  /// Activity discriminator, e.g. `"skill_tool_call"`.
  final String activityType;

  /// Structured payload describing the full activity state. Shape is
  /// specific to [activityType].
  final Map<String, dynamic> content;

  /// Event timestamp, or a wall-clock fallback if the event had none.
  final int timestamp;

  /// Creates a copy with the given fields replaced.
  ActivityRecord copyWith({
    String? messageId,
    String? activityType,
    Map<String, dynamic>? content,
    int? timestamp,
  }) {
    return ActivityRecord(
      messageId: messageId ?? this.messageId,
      activityType: activityType ?? this.activityType,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActivityRecord) return false;
    const mapEquals = DeepCollectionEquality();
    return messageId == other.messageId &&
        activityType == other.activityType &&
        timestamp == other.timestamp &&
        mapEquals.equals(content, other.content);
  }

  @override
  int get hashCode => Object.hash(
        messageId,
        activityType,
        timestamp,
        const DeepCollectionEquality().hash(content),
      );

  @override
  String toString() => 'ActivityRecord(messageId: $messageId, '
      'activityType: $activityType, timestamp: $timestamp)';
}
