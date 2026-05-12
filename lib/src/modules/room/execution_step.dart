import 'package:flutter/foundation.dart';

enum StepStatus { active, completed, failed }

enum StepType { thinking, toolCall }

@immutable
class ExecutionStep {
  const ExecutionStep({
    required this.label,
    required this.type,
    required this.status,
    required this.timestamp,
  });

  final String label;
  final StepType type;
  final StepStatus status;
  final Duration timestamp;

  ExecutionStep copyWith({
    String? label,
    StepType? type,
    StepStatus? status,
    Duration? timestamp,
  }) => .new(
    label: label ?? this.label,
    type: type ?? this.type,
    status: status ?? this.status,
    timestamp: timestamp ?? this.timestamp,
  );
}
