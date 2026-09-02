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

  /// How far into this tracker's stretch of the run the step last changed —
  /// set when it opens and replaced when it settles. Null when that instant
  /// cannot be established, which is a stored event that carried no emission
  /// time; the row then shows no elapsed figure rather than a wrong one.
  final Duration? timestamp;

  /// Settles this step at [at], which is null when the event settling it
  /// carried no emission time.
  ///
  /// [at] replaces the opening offset rather than falling back to it: when
  /// the settling instant is unknown, showing the opening figure would put a
  /// wrong number where an absent one belongs — the row reads as the instant
  /// the step ended, which is the one thing not known.
  ExecutionStep settled({required StepStatus status, required Duration? at}) =>
      ExecutionStep(
        label: label,
        type: type,
        status: status,
        timestamp: at,
      );
}
