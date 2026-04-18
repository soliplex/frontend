import 'dart:async';

import 'package:test/test.dart';
import 'package:ui_plugin/ui_plugin.dart';

// ---------------------------------------------------------------------------
// FakeUiRenderer
// ---------------------------------------------------------------------------

class FakeUiRenderer implements UiRenderer {
  final calls = <({String method, Map<String, Object?> args})>[];

  /// Controls the return value of [requestConfirm]. Defaults to `true`.
  bool Function(String verb)? confirmAnswer;

  /// Controls the return value of [showModal]. Defaults to `null`.
  String? Function(String title)? modalAnswer;

  /// Controls the return value of [showForm]. Defaults to `null`.
  Map<String, Object?>? Function(Map<String, Object?> schema)? formAnswer;

  void _record(String method, Map<String, Object?> args) =>
      calls.add((method: method, args: args));

  @override
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  }) async {
    _record(
        'requestConfirm', {'verb': verb, 'message': message, 'target': target});
    return confirmAnswer?.call(verb) ?? true;
  }

  @override
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  }) async {
    _record('showModal', {'title': title, 'body': body, 'actions': actions});
    return modalAnswer?.call(title);
  }

  @override
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  }) async {
    _record('showForm', {'schema': schema});
    return formAnswer?.call(schema);
  }

  @override
  void notify({required String kind, required String title, String? body}) {
    _record('notify', {'kind': kind, 'title': title, 'body': body});
  }

  @override
  void injectMessage({required String content, String? format}) {
    _record('injectMessage', {'content': content, 'format': format});
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UiPlugin _plugin(FakeUiRenderer renderer) => UiPlugin(renderer: renderer);

Future<Object?> _callHandler(
  UiPlugin plugin,
  String function,
  Map<String, Object?> args,
) {
  final fn = plugin.functions.firstWhere((f) => f.schema.name == function);
  return fn.handler(args);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ui_notify', () {
    test('delegates to renderer, returns null', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_notify',
        {'kind': 'info', 'title': 'Hello'},
      );

      expect(result, isNull);
      expect(r.calls, hasLength(1));
      expect(r.calls.first.method, 'notify');
      expect(r.calls.first.args['kind'], 'info');
      expect(r.calls.first.args['title'], 'Hello');
    });

    test('state does not change (fire-and-forget)', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      await _callHandler(p, 'ui_notify', {'kind': 'success', 'title': 'Done'});

      expect(p.state, isA<UiIdle>());
    });

    test('renderer error returns error string, no throw', () async {
      final p = UiPlugin(
        renderer: _ThrowingRenderer(on: 'notify'),
      );

      final result = await _callHandler(
        p,
        'ui_notify',
        {'kind': 'error', 'title': 'Boom'},
      );

      expect(result, isA<String>());
      expect(result.toString(), contains('ui_notify'));
    });
  });

  group('ui_show_modal', () {
    test('state transitions to UiModalOpen then back to UiIdle', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);
      final states = <UiSessionState>[];
      p.stateSignal.subscribe((s) => states.add(s));

      await _callHandler(
        p,
        'ui_show_modal',
        {'title': 'Welcome', 'body': 'Hello there'},
      );

      expect(states, [isA<UiIdle>(), isA<UiModalOpen>(), isA<UiIdle>()]);
    });

    test('returns tapped action label', () async {
      final r = FakeUiRenderer()..modalAnswer = (_) => 'Got it';
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_show_modal',
        {'title': 'MOTD', 'body': 'News'},
      );

      expect(result, 'Got it');
    });

    test('returns null when dismissed', () async {
      final r = FakeUiRenderer()..modalAnswer = (_) => null;
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_show_modal',
        {'title': 'MOTD', 'body': 'News'},
      );

      expect(result, isNull);
    });
  });

  group('ui_show_form', () {
    test('state transitions to UiFormOpen then back to UiIdle', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);
      final states = <UiSessionState>[];
      p.stateSignal.subscribe((s) => states.add(s));

      await _callHandler(
        p,
        'ui_show_form',
        {
          'schema': {'title': 'Settings'},
        },
      );

      expect(states, [isA<UiIdle>(), isA<UiFormOpen>(), isA<UiIdle>()]);
    });

    test('returns submitted map', () async {
      final r = FakeUiRenderer()..formAnswer = (_) => {'name': 'Alan'};
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_show_form',
        {
          'schema': {'fields': []},
        },
      );

      expect(result, {'name': 'Alan'});
    });

    test('returns null when dismissed', () async {
      final r = FakeUiRenderer()..formAnswer = (_) => null;
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_show_form',
        {
          'schema': {'fields': []},
        },
      );

      expect(result, isNull);
    });
  });

  group('ui_inject_message', () {
    test('delegates to renderer, returns null', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_inject_message',
        {'content': '**tip:** try /help'},
      );

      expect(result, isNull);
      expect(r.calls.first.method, 'injectMessage');
      expect(r.calls.first.args['content'], '**tip:** try /help');
    });

    test('passes format through', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      await _callHandler(
        p,
        'ui_inject_message',
        {'content': 'plain text', 'format': 'plain'},
      );

      expect(r.calls.first.args['format'], 'plain');
    });

    test('state does not change', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      await _callHandler(
        p,
        'ui_inject_message',
        {'content': 'hi'},
      );

      expect(p.state, isA<UiIdle>());
    });
  });

  group('ui_request_confirm', () {
    test('returns true when approved', () async {
      final r = FakeUiRenderer()..confirmAnswer = (_) => true;
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'delete', 'message': 'Delete this?'},
      );

      expect(result, true);
    });

    test('returns false when denied', () async {
      final r = FakeUiRenderer()..confirmAnswer = (_) => false;
      final p = _plugin(r);

      final result = await _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'clear', 'message': 'Clear history?'},
      );

      expect(result, false);
    });

    test('state transitions to UiAwaitingConfirm then UiIdle', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);
      final states = <UiSessionState>[];
      p.stateSignal.subscribe((s) => states.add(s));

      await _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'reset', 'message': 'Reset?'},
      );

      expect(states, [isA<UiIdle>(), isA<UiAwaitingConfirm>(), isA<UiIdle>()]);
    });

    test('concurrent confirms are serialised', () async {
      final r = FakeUiRenderer();
      final p = _plugin(r);

      final f1 = _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'delete', 'message': 'First?'},
      );
      final f2 = _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'clear', 'message': 'Second?'},
      );

      final results = await Future.wait([f1, f2]);
      // Both resolve without error; order is first-in-first-out.
      expect(results, everyElement(isNotNull));
      expect(r.calls.where((c) => c.method == 'requestConfirm'), hasLength(2));
    });

    test('renderer error returns error string, state resets', () async {
      final p = UiPlugin(renderer: _ThrowingRenderer(on: 'requestConfirm'));

      final result = await _callHandler(
        p,
        'ui_request_confirm',
        {'verb': 'delete', 'message': 'Boom?'},
      );

      expect(result.toString(), contains('ui_request_confirm'));
      expect(p.state, isA<UiIdle>());
    });
  });
}

// ---------------------------------------------------------------------------
// _ThrowingRenderer — test double that throws on a specific method
// ---------------------------------------------------------------------------

class _ThrowingRenderer implements UiRenderer {
  _ThrowingRenderer({required this.on});

  final String on;

  Never _throw(String method) => throw StateError('$method deliberately threw');

  @override
  Future<bool> requestConfirm({
    required String verb,
    required String message,
    String? target,
  }) async {
    if (on == 'requestConfirm') _throw('requestConfirm');
    return true;
  }

  @override
  Future<String?> showModal({
    required String title,
    required String body,
    List<String>? actions,
  }) async {
    if (on == 'showModal') _throw('showModal');
    return null;
  }

  @override
  Future<Map<String, Object?>?> showForm({
    required Map<String, Object?> schema,
  }) async {
    if (on == 'showForm') _throw('showForm');
    return null;
  }

  @override
  void notify({required String kind, required String title, String? body}) {
    if (on == 'notify') _throw('notify');
  }

  @override
  void injectMessage({required String content, String? format}) {
    if (on == 'injectMessage') _throw('injectMessage');
  }
}
