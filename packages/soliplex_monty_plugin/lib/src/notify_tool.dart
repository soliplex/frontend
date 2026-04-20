import 'package:soliplex_monty_plugin/src/soliplex_tool.dart';

/// A notification event emitted by the `notify_show` tool.
class NotifyEvent {
  /// Creates a [NotifyEvent].
  const NotifyEvent({
    required this.kind,
    required this.title,
    required this.body,
  });

  /// Severity: `'info'`, `'success'`, `'error'`, or `'warning'`.
  final String kind;

  /// Short headline shown in the SnackBar.
  final String title;

  /// Optional body text shown below the title.
  final String body;
}

/// Builds the `notify_show` tool that emits [NotifyEvent]s via [emit].
SoliplexTool buildNotifyTool(void Function(NotifyEvent) emit) {
  return SoliplexTool(
    name: 'notify_show',
    description: 'Show a notification. kind: info|success|error|warning.',
    parameters: const {
      'type': 'object',
      'properties': {
        'kind': {'type': 'string'},
        'title': {'type': 'string'},
        'body': {'type': 'string'},
      },
      'required': ['kind', 'title', 'body'],
    },
    handler: (args) async {
      emit(
        NotifyEvent(
          kind: args['kind'] as String? ?? 'info',
          title: args['title'] as String? ?? '',
          body: args['body'] as String? ?? '',
        ),
      );
      return {'shown': true};
    },
  );
}
