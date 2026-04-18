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
    this.toolCallId,
    this.args,
  });

  final String label;
  final StepType type;
  final StepStatus status;
  final Duration timestamp;
  final String? toolCallId;
  final String? args;

  ExecutionStep copyWith({
    StepStatus? status,
    Duration? timestamp,
    String? args,
  }) =>
      ExecutionStep(
        label: label,
        type: type,
        status: status ?? this.status,
        timestamp: timestamp ?? this.timestamp,
        toolCallId: toolCallId,
        args: args ?? this.args,
      );
}
