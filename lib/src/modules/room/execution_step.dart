import 'package:flutter/foundation.dart';

enum StepStatus { active, completed, failed }

@immutable
class ExecutionStep {
  const ExecutionStep({
    required this.label,
    required this.status,
    required this.timestamp,
    this.toolCallId,
    this.args,
  });

  final String label;
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
        status: status ?? this.status,
        timestamp: timestamp ?? this.timestamp,
        toolCallId: toolCallId,
        args: args ?? this.args,
      );
}
