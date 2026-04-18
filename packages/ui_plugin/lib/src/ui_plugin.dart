import 'dart:async';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'errors.dart';
import 'ui_renderer.dart';
import 'ui_session_state.dart';

// ---------------------------------------------------------------------------
// Schema constants
// ---------------------------------------------------------------------------

const _uiNotifySchema = HostFunctionSchema(
  name: 'ui_notify',
  description:
      "Pop a non-blocking toast. kind: 'info'|'success'|'warning'|'error'.",
  params: [
    HostParam(
      name: 'kind',
      type: HostParamType.string,
      description: "Severity: 'info', 'success', 'warning', or 'error'.",
    ),
    HostParam(name: 'title', type: HostParamType.string, description: 'Title.'),
    HostParam(
      name: 'body',
      type: HostParamType.string,
      description: 'Optional detail text.',
      isRequired: false,
    ),
  ],
);

const _uiShowModalSchema = HostFunctionSchema(
  name: 'ui_show_modal',
  description:
      'Show a blocking modal with a title, body, and optional action buttons. '
      'Returns the label of the tapped action, or null if dismissed.',
  params: [
    HostParam(
      name: 'title',
      type: HostParamType.string,
      description: 'Modal heading.',
    ),
    HostParam(
      name: 'body',
      type: HostParamType.string,
      description: 'Modal body text (markdown supported).',
    ),
    HostParam(
      name: 'actions',
      type: HostParamType.list,
      description: 'Button labels. Defaults to a single dismiss button.',
      isRequired: false,
    ),
  ],
);

const _uiShowFormSchema = HostFunctionSchema(
  name: 'ui_show_form',
  description: 'Show a blocking form modal described by a JSON schema. '
      'Returns the submitted field map, or null if dismissed.',
  params: [
    HostParam(
      name: 'schema',
      type: HostParamType.map,
      description: 'JSON schema describing the form fields.',
    ),
  ],
);

const _uiInjectMessageSchema = HostFunctionSchema(
  name: 'ui_inject_message',
  description:
      'Inject an ephemeral, client-only informational message into the active '
      'chat area. Not persisted. Disappears on reload or navigation.',
  params: [
    HostParam(
      name: 'content',
      type: HostParamType.string,
      description: 'Message content.',
    ),
    HostParam(
      name: 'format',
      type: HostParamType.string,
      description: "Render format: 'markdown' (default) or 'plain'.",
      isRequired: false,
    ),
  ],
);

const _uiRequestConfirmSchema = HostFunctionSchema(
  name: 'ui_request_confirm',
  description: 'Ask the user to confirm a destructive verb. '
      'Returns true if approved, false if denied.',
  params: [
    HostParam(
      name: 'verb',
      type: HostParamType.string,
      description: "Action label, e.g. 'delete', 'clear', 'reset'.",
    ),
    HostParam(
      name: 'message',
      type: HostParamType.string,
      description: 'Human-readable description of what will happen.',
    ),
    HostParam(
      name: 'target',
      type: HostParamType.string,
      description: 'Optional identifier of the affected resource (for audit).',
      isRequired: false,
    ),
  ],
);

// ---------------------------------------------------------------------------
// UiPlugin
// ---------------------------------------------------------------------------

/// Gives Python scripts a generic UI surface: modals, toasts, forms,
/// ephemeral inline messages, and destructive-action confirmation gates.
///
/// All visible effects are delegated to an embedder-provided [UiRenderer].
/// The plugin is renderer-agnostic — Soliplex provides [SoliplexUiRenderer];
/// tests supply [FakeUiRenderer].
///
/// ## Confirm serialisation
///
/// If a confirm dialog is already open when a second [ui_request_confirm] call
/// arrives, the second call awaits the first. This prevents modal flooding
/// when Python calls confirm in a loop.
///
/// ## Error discipline
///
/// Renderer errors are caught, state is reset to [UiIdle], and the error is
/// returned as a string to Python — never thrown across the bridge boundary.
class UiPlugin extends MontyPlugin with StatefulPlugin<UiSessionState> {
  /// Creates a [UiPlugin] backed by [renderer].
  ///
  /// [renderer] is required — there is no null renderer path at runtime.
  UiPlugin({required UiRenderer renderer}) : _renderer = renderer {
    setInitialState(const UiIdle());
  }

  final UiRenderer _renderer;

  // Serialises concurrent confirm requests.
  Future<bool>? _pendingConfirm;

  @override
  String get namespace => 'ui';

  @override
  String? get systemPromptContext =>
      'Drive the host UI: show modals (ui_show_modal), forms (ui_show_form), '
      'toasts (ui_notify), inline messages (ui_inject_message), and '
      'confirmation gates (ui_request_confirm).';

  @override
  List<HostFunction> get functions => [
        HostFunction(schema: _uiNotifySchema, handler: _handleNotify),
        HostFunction(schema: _uiShowModalSchema, handler: _handleShowModal),
        HostFunction(schema: _uiShowFormSchema, handler: _handleShowForm),
        HostFunction(
          schema: _uiInjectMessageSchema,
          handler: _handleInjectMessage,
        ),
        HostFunction(
          schema: _uiRequestConfirmSchema,
          handler: _handleRequestConfirm,
        ),
      ];

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Future<Object?> _handleNotify(Map<String, Object?> args) async {
    try {
      _renderer.notify(
        kind: args.str('kind'),
        title: args.str('title'),
        body: args.strOrNull('body'),
      );
    } catch (e) {
      return RendererUnavailableError('ui_notify', e).toString();
    }
    return null;
  }

  Future<Object?> _handleShowModal(Map<String, Object?> args) async {
    final title = args.str('title');
    state = UiModalOpen(title: title);
    try {
      final result = await _renderer.showModal(
        title: title,
        body: args.str('body'),
        actions: (args['actions'] as List?)?.cast<String>(),
      );
      return result;
    } catch (e) {
      return RendererUnavailableError('ui_show_modal', e).toString();
    } finally {
      state = const UiIdle();
    }
  }

  Future<Object?> _handleShowForm(Map<String, Object?> args) async {
    final schema = args.mapArg('schema');
    state = UiFormOpen(schemaKey: schema.hashCode.toString());
    try {
      final result = await _renderer.showForm(schema: schema);
      return result;
    } catch (e) {
      return RendererUnavailableError('ui_show_form', e).toString();
    } finally {
      state = const UiIdle();
    }
  }

  Future<Object?> _handleInjectMessage(Map<String, Object?> args) async {
    try {
      _renderer.injectMessage(
        content: args.str('content'),
        format: args.strOrNull('format'),
      );
    } catch (e) {
      return RendererUnavailableError('ui_inject_message', e).toString();
    }
    return null;
  }

  Future<Object?> _handleRequestConfirm(Map<String, Object?> args) async {
    // Serialise: if a confirm is already pending, await it first.
    final existing = _pendingConfirm;
    if (existing != null) await existing.catchError((_) => false);

    final verb = args.str('verb');
    final message = args.str('message');
    final target = args.strOrNull('target');

    state = UiAwaitingConfirm(verb: verb, message: message, target: target);

    final completer = Completer<bool>();
    _pendingConfirm = completer.future;

    try {
      final approved = await _renderer.requestConfirm(
        verb: verb,
        message: message,
        target: target,
      );
      completer.complete(approved);
      return approved;
    } catch (e) {
      completer.complete(false);
      return RendererUnavailableError('ui_request_confirm', e).toString();
    } finally {
      _pendingConfirm = null;
      state = const UiIdle();
    }
  }
}
