# soliplex_client

Pure Dart client library for the Soliplex backend. No Flutter dependencies.

## Quick Reference

```bash
dart pub get
dart format . --set-exit-if-changed
dart analyze --fatal-infos
dart test
```

## Package Purpose

Provides REST API access, AG-UI streaming, domain models, and HTTP transport
for Soliplex. Used by `soliplex_agent`, `soliplex_cli`, and the Flutter app.

## Key Interfaces

### SoliplexHttpClient (`lib/src/http/soliplex_http_client.dart`)

Core HTTP interface. Two methods: `request()` (REST) and `requestStream()`
(SSE). All decorators and platform clients implement this.

### HttpTransport (`lib/src/http/http_transport.dart`)

Top-level transport. Handles JSON encoding, status-to-exception mapping,
and CancelToken wrapping. Application code uses this, not raw clients.

### HttpObserver (`lib/src/http/http_observer.dart`)

Observer interface for monitoring. Five event types: request, response,
error, stream start, stream end.

## HTTP Decorator Chain

```text
HttpTransport -> ConcurrencyLimitingHttpClient -> RefreshingHttpClient
  -> AuthenticatedHttpClient -> ObservableHttpClient -> Platform Client
```

Each decorator implements `SoliplexHttpClient` and delegates to an inner
client. Concurrency is outermost so that per-request auth work (token
fetch, proactive refresh) runs at dispatch time rather than at enqueue
time — keeping queued requests from holding stale tokens.

## Directory Structure

```text
lib/src/
  api/           REST API client, AG-UI mapper
  application/   Event processing, streaming state
  auth/          OIDC discovery, token refresh
  domain/        Immutable data models
  errors/        SoliplexException hierarchy
  http/          Transport layer (decorator chain)
  schema/        Generated AG-UI schemas
  utils/         CancelToken, UrlBuilder
```

## Modification Rules

- Keep pure Dart: no Flutter imports
- All exceptions must be `SoliplexException` subtypes
- All models must be `@immutable`
- New decorators must forward `cancelToken` on `requestStream`
- New decorators must forward `timeout` on `request`
- Export new public types from the barrel `lib/soliplex_client.dart`
- Platform-specific code goes in `soliplex_client_native`, not here

## CancelToken Import Pattern

The barrel `lib/soliplex_client.dart` hides ag_ui's `CancelToken` and
exports ours directly. Consumers get `CancelToken` from the barrel with
no extra imports needed:

```dart
import 'package:soliplex_client/soliplex_client.dart';
// CancelToken is our type — ag_ui's is hidden at the barrel level.
```

Cross-package code (e.g., `soliplex_client_native`) can also use the
dedicated export `package:soliplex_client/cancel_token.dart`.

## What NOT to Touch

- `lib/src/schema/`: generated code, do not edit manually
- Observer event redaction in `http_redactor.dart`: security-critical
- Exception hierarchy in `errors/exceptions.dart`: widely consumed,
  changes cascade to all packages and the Flutter app

## Tests

```bash
dart test                          # all tests
dart test test/http/               # HTTP layer only
dart test test/api/                # API client only
dart test test/domain/             # domain models only
```

Test helpers: use `mocktail` for mocking. See existing tests for patterns.
Mirror `lib/` structure in `test/`.

## Dependencies

- `http` -- pure Dart HTTP client
- `ag_ui` -- AG-UI protocol types
- `meta` -- `@immutable` annotation
