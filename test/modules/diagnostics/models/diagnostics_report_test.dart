import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/diagnostics_report.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';

void main() {
  final at = DateTime.utc(2026, 8, 18, 7, 51);

  String report({
    List<HttpEventGroup> groups = const [],
    List<String>? renderedLogRecords = const [],
    List<ConcurrencyWaitEvent> concurrencyEvents = const [],
    String logLevel = 'WARNING',
    DateTime? generatedAt,
  }) =>
      buildDiagnosticsReport(
        appName: 'Test',
        groups: groups,
        generatedAt: generatedAt ?? at,
        renderedLogRecords: renderedLogRecords,
        concurrencyEvents: concurrencyEvents,
        logLevel: logLevel,
      );

  test('a failed request reports the platform error, not just the message', () {
    // The banner shows only the localized sentence; the domain and numeric
    // code are what actually name the failure.
    final group = HttpEventGroup(
      requestId: 'r1',
      error: HttpErrorEvent(
        requestId: 'r1',
        timestamp: at,
        method: 'GET',
        uri: Uri.parse('https://ai.example.mil/api/login'),
        exception: NetworkException(
          message: 'Client error: A server with the specified hostname could '
              'not be found.',
          originalError: 'NSErrorClientException: A server with the specified '
              'hostname could not be found. '
              '[domain=NSURLErrorDomain, code=-1003]',
        ),
        duration: const Duration(milliseconds: 32),
      ),
    );

    final out = report(groups: [group]);

    expect(out, contains('https://ai.example.mil/api/login'));
    expect(out, contains('code=-1003'));
    expect(out, contains('FAILED after 32ms'));
  });

  test('a failed stream reports its outcome, not a bare URL', () {
    // A streamed exchange emits no request, response or error event, only
    // stream start/end, so reading only those three renders every agent run —
    // the traffic most worth reporting — as a URL and nothing else.
    final group = HttpEventGroup(
      requestId: 'r2',
      streamStart: HttpStreamStartEvent(
        requestId: 'r2',
        timestamp: at,
        method: 'POST',
        uri: Uri.parse('https://ai.example.mil/api/v1/rooms/r1/agui/t1/run-1'),
        headers: const {'accept': 'text/event-stream'},
      ),
      streamEnd: HttpStreamEndEvent(
        requestId: 'r2',
        timestamp: at.add(const Duration(seconds: 4)),
        bytesReceived: 2048,
        duration: const Duration(seconds: 4),
        error: const NetworkException(
          message: 'Connection closed',
          originalError: '[domain=NSURLErrorDomain, code=-1005]',
        ),
      ),
    );

    final out = report(groups: [group]);

    expect(out, contains('/api/v1/rooms/r1/agui/t1/run-1'));
    // The request half survives even though there is no request event.
    expect(out, contains('sent: 2026-08-18T07:51:00.000Z'));
    expect(out, contains('accept: text/event-stream'));
    // And the outcome.
    expect(out, contains('outcome: stream error'));
    expect(out, contains('duration: 4000ms'));
    expect(out, contains('bytesReceived: 2048'));
    expect(out, contains('STREAM FAILED'));
    expect(out, contains('code=-1005'));
  });

  test('timestamps are UTC so a report lines up against server logs', () {
    // Fed a LOCAL DateTime on purpose. `toIso8601String` emits the trailing Z
    // only when `isUtc`, so this fails if the conversion is dropped — which a
    // UTC input could not detect, and CI runs in UTC.
    final out = report(generatedAt: DateTime(2026, 8, 18, 7, 51));

    expect(out, contains('Generated: '));
    expect(
      RegExp(r'Generated: \S+Z$', multiLine: true).hasMatch(out),
      isTrue,
      reason: 'the generated-at line must carry a UTC offset',
    );
  });

  test('an exchange still in flight reports that, not silence', () {
    // The reason a report gets exported at all is often a run that is hanging,
    // so the one entry that matters has no response, no stream end and no
    // error. Printing nothing for it made it look like a request that came
    // back empty.
    final group = HttpEventGroup(
      requestId: 'r3',
      streamStart: HttpStreamStartEvent(
        requestId: 'r3',
        timestamp: at,
        method: 'POST',
        uri: Uri.parse('https://ai.example.mil/api/v1/rooms/r1/agui/t1/run-9'),
      ),
    );

    final out = report(groups: [group]);

    expect(out, contains('/api/v1/rooms/r1/agui/t1/run-9'));
    expect(out, contains('outcome: streaming'));
  });

  test('an empty log section is stated rather than omitted', () {
    // "No records" and "records were never collected" lead a reader to
    // different conclusions; a missing section cannot distinguish them.
    final out = report();

    expect(out, contains('Log level floor: WARNING'));
    expect(out, contains('Log records (0)'));
    expect(out, contains('No log records captured.'));
  });

  test('an uncollected log section says so instead of claiming none', () {
    // The case a host app hits when it installs no memory sink. Reporting it
    // as an empty capture would tell the reader the code logged nothing.
    final out = report(renderedLogRecords: null);

    expect(out, contains('Log records (not collected)'));
    expect(out, contains('No log sink is installed'));
    expect(out, isNot(contains('No log records captured.')));
  });

  test('request pool waits are reported, and their absence is too', () {
    // A request queued behind the pool's cap looks slow for reasons unrelated
    // to the server it is calling, so the wait has to be visible — and the
    // section is written either way, for the same reason the log section is.
    final waited = report(
      concurrencyEvents: [
        ConcurrencyWaitEvent(
          acquisitionId: 'a1',
          timestamp: at,
          uri: Uri.parse('https://ai.example.mil/api/login'),
          waitDuration: const Duration(milliseconds: 1400),
          queueDepthAtEnqueue: 3,
          slotsInUseAfterAcquire: 6,
        ),
      ],
    );

    expect(waited, contains('Request pool waits (1)'));
    expect(waited, contains('waited 1400ms'));

    expect(report(), contains('No requests waited for a pool slot.'));
  });
}
