// Integration tests for UiPlugin end-to-end through MontyScriptEnvironment.
// Verifies Python host-function calls reach the UiRenderer on both backends.
//
// Run with:
//   dart test test/integration/ui_plugin_integration_test.dart -p vm
//   dart test test/integration/ui_plugin_integration_test.dart -p chrome
@Tags(['monty'])
library;

import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';
import 'package:ui_plugin/ui_plugin.dart';

// ---------------------------------------------------------------------------
// Stub context
// ---------------------------------------------------------------------------

class _StubContext implements ToolExecutionContext {
  @override
  CancelToken get cancelToken => CancelToken();

  @override
  Future<AgentSession> spawnChild({required String prompt, String? roomId}) =>
      throw UnimplementedError();

  @override
  void emitEvent(ExecutionEvent event) {}

  @override
  T? getExtension<T extends SessionExtension>() => null;

  @override
  Future<ApprovalResult> requestApproval({
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) async =>
      const AllowOnce();

  @override
  Future<String> delegateTask({
    required String prompt,
    String? roomId,
    Duration? timeout,
  }) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Capture renderer — records all calls synchronously
// ---------------------------------------------------------------------------

class _CaptureRenderer implements UiRenderer {
  final List<({String kind, String title, String? body})> notifications = [];
  final List<({String content, String? format})> injected = [];
  final List<String> modals = [];
  final List<Map<String, Object?>> forms = [];
  final List<({String verb, String message, String? target})> confirms = [];

  String? nextModalResult;
  Map<String, Object?>? nextFormResult;
  bool nextConfirmResult = true;

  @override
  void notify({required String kind, required String title, String? body}) {
    notifications.add((kind: kind, title: title, body: body));
  }

  @override
  void injectMessage({required String content, String? format}) {
    injected.add((content: content, format: format));
  }

  @override
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  }) async {
    modals.add(title);
    return nextModalResult;
  }

  @override
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  }) async {
    forms.add(schema);
    return nextFormResult;
  }

  @override
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  }) async {
    confirms.add((verb: verb, message: message, target: target));
    return nextConfirmResult;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _CaptureRenderer renderer;
  late MontyScriptEnvironment env;

  setUp(() {
    renderer = _CaptureRenderer();
    env = MontyScriptEnvironment(
      tools: const [],
      plugins: [UiPlugin(renderer: renderer)],
    );
  });

  tearDown(() => env.dispose());

  ClientTool executePython() =>
      env.tools.firstWhere((t) => t.definition.name == 'execute_python');

  Future<String> exec(String code) {
    return executePython().executor(
      ToolCallInfo(
        id: 'tc',
        name: 'execute_python',
        arguments: jsonEncode({'code': code}),
      ),
      _StubContext(),
    );
  }

  group('UiPlugin integration', () {
    test(
      'ui_inject_message delivers content to renderer',
      () async {
        await exec('ui_inject_message(content="Hello from Python!")');

        expect(renderer.injected, hasLength(1));
        expect(renderer.injected.first.content, equals('Hello from Python!'));
        expect(renderer.injected.first.format, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_inject_message passes format hint to renderer',
      () async {
        await exec(
          'ui_inject_message(content="plain text", format="plain")',
        );

        expect(renderer.injected.first.format, equals('plain'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_notify delivers kind, title, and body to renderer',
      () async {
        await exec(
          'ui_notify(kind="success", title="Done", body="All good")',
        );

        expect(renderer.notifications, hasLength(1));
        final n = renderer.notifications.first;
        expect(n.kind, equals('success'));
        expect(n.title, equals('Done'));
        expect(n.body, equals('All good'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_notify without body omits body',
      () async {
        await exec('ui_notify(kind="info", title="FYI")');

        expect(renderer.notifications.first.body, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_show_modal reaches renderer with title',
      () async {
        renderer.nextModalResult = 'OK';

        await exec(
          'ui_show_modal(title="Confirm", body="Are you sure?")',
        );

        expect(renderer.modals, contains('Confirm'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_show_form passes schema to renderer',
      () async {
        renderer.nextFormResult = {'name': 'Alice'};

        await exec(
          'ui_show_form(schema={"type": "object", "properties": '
          '{"name": {"type": "string"}}})',
        );

        expect(renderer.forms, hasLength(1));
        expect(renderer.forms.first['type'], equals('object'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_request_confirm delivers verb and message to renderer',
      () async {
        await exec(
          'ui_request_confirm(verb="delete", message="Delete all data?")',
        );

        expect(renderer.confirms, hasLength(1));
        final c = renderer.confirms.first;
        expect(c.verb, equals('delete'));
        expect(c.message, equals('Delete all data?'));
        expect(c.target, isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'ui_request_confirm passes optional target to renderer',
      () async {
        await exec(
          'ui_request_confirm('
          'verb="reset", message="Reset config?", target="prod")',
        );

        expect(renderer.confirms.first.target, equals('prod'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'multiple ui_inject_message calls accumulate',
      () async {
        await exec(
          'ui_inject_message(content="first")\n'
          'ui_inject_message(content="second")\n'
          'ui_inject_message(content="third")',
        );

        expect(renderer.injected, hasLength(3));
        expect(
          renderer.injected.map((m) => m.content),
          equals(['first', 'second', 'third']),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
