/// How much of a model's context window a conversation occupies.
///
/// The counting happens on the server, which is the only place that can
/// see the whole request: the agent's instructions, capability
/// instructions, tool and MCP schemas, the chat template, and any
/// evidence compaction applied on the way out. What lives here is the
/// shape a reading arrives in, not the arithmetic that produced it.
library;

export 'context_segment.dart';
export 'context_usage.dart';
export 'draft_estimator.dart';
