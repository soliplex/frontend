import 'package:flutter/foundation.dart';

@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.activityType,
    required this.content,
    required this.timestamp,
  });

  final String activityType;
  final Map<String, dynamic> content;
  final Duration timestamp;
}
