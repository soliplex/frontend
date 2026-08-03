import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A persisted AG-UI activity snapshot.
///
/// One record per `ActivitySnapshotEvent` folded into a conversation,
/// whether it arrived on a live stream or from stored thread history.
/// AG-UI defines an activity as an id-keyed store of opaque [content] and
/// names no vocabulary for what is inside it, so [content] is stored
/// verbatim and this layer reads no key of its own choosing out of it —
/// only the RFC 6902 pointers a delta supplies.
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

  /// Activity discriminator. The spec names no vocabulary for it, so any
  /// value a producer sends is valid and none is privileged here.
  final String activityType;

  /// Payload describing the full activity state, stored as it arrived.
  /// Opaque to this layer; its shape is a producer's own convention.
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
