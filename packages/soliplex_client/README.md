# soliplex_client

Pure Dart client for the Soliplex backend HTTP and AG-UI APIs.

## Quick Start

```bash
cd packages/soliplex_client
dart pub get
dart test
dart format . --set-exit-if-changed
dart analyze --fatal-infos
```

## Architecture

### API Layer

- `SoliplexApi` -- primary HTTP client for all backend operations (rooms, threads, runs, feedback, quizzes, documents)
- `AgUiMessageMapper` -- converts between backend message formats and domain models
- `FetchAuthProviders` -- retrieves OIDC provider configurations

### Application Layer

- `AgUiEventProcessor` (`processEvent`) -- pure-function state machine that processes AG-UI events into `Conversation` + `StreamingState`
- `RunFold` -- folds one AG-UI run's events into a `Conversation`; the live stream and a reopened thread's stored runs both go through it, so a run reads the same either way
- `CitationExtractor` -- extracts citation references from streamed content
- `JsonPatch` -- applies JSON-patch deltas to AG-UI state
- `StreamingState` -- ephemeral state tracking during an active SSE stream
- `ToolRegistry` / `ClientTool` / `ToolExecutor` -- client-side tool definition, registration, and execution

### Domain Models

- `Room`, `RoomAgent`, `RoomTool` -- room configuration and capabilities
- `Conversation`, `ChatMessage`, `MessageState` -- chat state
- `ThreadInfo`, `ThreadHistory`, `RunInfo` -- thread and run metadata
- `SourceReference`, `RagDocument`, `ChunkVisualization` -- RAG context
- `Quiz` -- quiz definitions and answers
- `ToolCallInfo`, `McpClientToolset` -- tool invocation data

### HTTP Layer

- `SoliplexHttpClient` -- abstract interface for HTTP operations
- `DartHttpClient` -- default implementation using `package:http`
- `HttpTransport` -- transport abstraction wrapping `SoliplexHttpClient`
- `HttpClientAdapter` -- adapts `SoliplexHttpClient` to `http.BaseClient` for `ag_ui`
- `AuthenticatedHttpClient` / `RefreshingHttpClient` -- token management decorators
- `ObservableHttpClient` / `HttpObserver` -- request/response observation hooks

### Auth

- `OidcDiscovery` -- OIDC well-known endpoint discovery
- `TokenRefreshService` -- automatic token refresh

### Errors

- `NetworkException`, `ApiException` -- typed HTTP errors

## Dependencies

- `ag_ui` -- AG-UI protocol types (re-exported)
- `http` -- Dart HTTP client
- `collection` -- collection utilities
- `meta` -- annotations

## Example

```dart
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  // 1. Create the HTTP transport
  final httpClient = DartHttpClient();
  final transport = HttpTransport(client: httpClient);
  final urlBuilder = UrlBuilder('http://localhost:8000');

  // 2. Create the API client
  final api = SoliplexApi(transport: transport, urlBuilder: urlBuilder);

  // 3. List rooms
  final rooms = await api.getRooms();
  for (final room in rooms) {
    print('Room: ${room.id}');
  }

  // 4. Create a thread and run
  final (threadInfo, _) = await api.createThread('plain');
  final run = await api.createRun('plain', threadInfo.id);
  print('Run ${run.id} started');

  api.close();
}
```
