/// Pure Dart agent orchestration for Soliplex AI runtime.
///
/// This package provides the core types and orchestration logic for
/// running AI agents. It depends only on `soliplex_client` and
/// `soliplex_logging` — no Flutter imports allowed.
library;

// Re-export signal types for consumers.
export 'package:signals_core/signals_core.dart'
    show ReadonlySignal, Signal, computed;
// Re-export domain types, AG-UI events, and HTTP interfaces. The frontend
// imports soliplex_agent — not soliplex_client directly. Internal plumbing
// (DartHttpClient, ObservableHttpClient, etc.) stays hidden behind factories.
export 'package:soliplex_client/soliplex_client.dart'
    hide
        AuthenticatedHttpClient,
        DartHttpClient,
        HttpTransport,
        ObservableHttpClient,
        OidcDiscoveryDocument,
        RefreshingHttpClient,
        SoliplexApi,
        UrlBuilder,
        convertToAgui,
        defaultHttpTimeout,
        fetchAuthProviders;
// Re-export logging types so consumers don't need a direct soliplex_logging
// dependency just to construct an AgentRuntime.
export 'package:soliplex_logging/soliplex_logging.dart' show LogManager, Logger;

// ── Host API ──
export 'src/host/agent_api.dart';
export 'src/host/blackboard_api.dart';
export 'src/host/direct_blackboard_api.dart';
export 'src/host/form_api.dart';
export 'src/host/host_api.dart';
export 'src/host/mobile_platform_constraints.dart';
export 'src/host/native_platform_constraints.dart';
export 'src/host/platform_constraints.dart';
export 'src/host/runtime_agent_api.dart';
export 'src/host/web_platform_constraints.dart';
// ── HTTP ──
export 'src/http/create_agent_http_client.dart';
export 'src/http/discover_auth_providers.dart';
// ── Models ──
export 'src/models/agent_result.dart';
export 'src/models/failure_reason.dart';
export 'src/models/thread_key.dart';
// ── Orchestration ──
export 'src/orchestration/ag_ui_llm_provider.dart';
export 'src/orchestration/agent_llm_provider.dart';
export 'src/orchestration/chat_fn_llm_provider.dart';
export 'src/orchestration/execution_event.dart';
export 'src/orchestration/run_state.dart';
export 'src/orchestration/streaming_llm_provider.dart';
// ── Runtime ──
export 'src/runtime/agent_runtime.dart';
export 'src/runtime/agent_session.dart';
export 'src/runtime/agent_session_state.dart';
export 'src/runtime/agent_ui_delegate.dart';
export 'src/runtime/multi_server_runtime.dart';
export 'src/runtime/server_connection.dart';
export 'src/runtime/server_registry.dart';
export 'src/runtime/session_extension.dart';
// ── Scripting ──
export 'src/scripting/script_environment.dart';
export 'src/scripting/scripting_state.dart';
// ── Tools ──
export 'src/tools/tool_execution_context.dart';
export 'src/tools/tool_registry.dart';
