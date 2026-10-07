/// How much of a model's context window a conversation occupies.
///
/// The counting happens on the server, which is the only place that can
/// see the whole request: the agent's instructions, capability
/// instructions, tool and MCP schemas, the chat template, and any
/// evidence compaction applied on the way out. What lives here is the
/// context reading a thread presents, and the estimators that fill in
/// what no run has measured.
library;

export 'context_usage.dart';
export 'draft_estimator.dart';
export 'transcript_estimator.dart';
