import 'package:soliplex_client/soliplex_client.dart';

import '../../../../version.dart';
import 'http_event_group.dart';

/// Renders the captured traffic and log records as a plain-text report a user
/// can send to support.
///
/// The HTTP sections are redacted at capture time by `HttpRedactor`, which
/// replaces the values of `Authorization`, cookies and token-bearing query
/// parameters with a placeholder — the names still appear, the secrets do not.
/// So they carry hostnames, paths, status codes, timings and error detail, and
/// no credentials.
///
/// The log section is not redacted by anything. What it carries is whatever
/// the app logs: server and discovery URLs, hostnames, token expiry times.
/// That is deployment detail rather than credentials, but nothing enforces it,
/// so a logger that starts recording a secret puts the secret in this report.
///
/// Errors are rendered with the underlying platform exception alongside the
/// friendly message shown in the UI: on Apple platforms
/// `NSErrorClientException` appends the domain and numeric code (e.g.
/// `[domain=NSURLErrorDomain, code=-1003]`), which names a failure far more
/// precisely than its localized sentence.
///
/// Every timestamp this function writes is UTC, and the log lines arrive
/// already formatted that way by `formatLogRecord`. A report is read beside
/// server logs on another machine, and a local wall-clock time with no offset
/// cannot be lined up against them.
String buildDiagnosticsReport({
  required String appName,
  required List<HttpEventGroup> groups,
  required DateTime generatedAt,
  required List<ConcurrencyWaitEvent> concurrencyEvents,

  /// One entry per record, already rendered by `formatLogRecord`. An entry
  /// spans several lines when it carries a stack trace.
  ///
  /// Null when nothing is collecting records at all, which is a different
  /// report from one where nothing was recorded — see the log section below.
  required List<String>? renderedLogRecords,
  required String logLevel,
}) {
  final out = StringBuffer()
    ..writeln('$appName diagnostics report')
    ..writeln('Generated: ${_utc(generatedAt)}')
    ..writeln('App version: $soliplexVersion')
    ..writeln('Requests captured: ${groups.length}');
  // Naming the floor keeps a reader from concluding nothing happened when
  // records below it were simply never recorded — a release build keeps only
  // warnings and above.
  out
    ..writeln('Log level floor: $logLevel')
    ..writeln();

  if (groups.isEmpty) {
    out.writeln('No requests captured.');
  }

  for (final group in groups) {
    out
      ..writeln('--- ${group.methodLabel} ${group.uri}')
      ..writeln('    requestId: ${group.requestId}')
      // Reads through the group rather than `group.request`, because a
      // streamed exchange has no request event at all — the same detail
      // arrives on its stream-start event instead.
      ..writeln('    sent: ${_utc(group.timestamp)}');
    for (final header in group.requestHeaders.entries) {
      out.writeln('    > ${header.key}: ${header.value}');
    }

    // Written for every exchange, whatever kind, and whether or not it
    // finished. An exchange still in flight is the reason a report gets
    // exported at all — a hanging agent run — and printing nothing for it left
    // the one entry that mattered indistinguishable from a request that came
    // back empty. `statusDescription` names the outcome and carries the numeric
    // code where there is one, so no separate line is needed for the code.
    out.writeln('    outcome: ${group.statusDescription}');

    if (group.response case final response?) {
      out
        ..writeln('    duration: ${response.duration.inMilliseconds}ms')
        // Printed for the same reason a stream's bytesReceived is: without it
        // a 200 that returned nothing reads exactly like a 200 that returned
        // the answer.
        ..writeln('    bodySize: ${response.bodySize}');
    }

    // A stream carries its timing, its size and its failure detail on
    // stream-end rather than on a response or error event, so without this arm
    // an agent run — the traffic most worth reporting — would be named and
    // given an outcome with nothing to say how long it ran, how much it
    // returned, or what the platform error behind a failure was.
    if (group.streamEnd case final end?) {
      out
        ..writeln('    duration: ${end.duration.inMilliseconds}ms')
        ..writeln('    bytesReceived: ${end.bytesReceived}');
      if (end.error case final error?) {
        out
          ..writeln('    STREAM FAILED: $error')
          ..writeln('    platform: ${error.originalError ?? '-'}');
      }
    }

    if (group.error case final error?) {
      out
        ..writeln('    FAILED after ${error.duration.inMilliseconds}ms')
        ..writeln('    error: ${error.exception}')
        // The wrapped platform error, when there is one, carries the domain
        // and numeric code the friendly message drops.
        ..writeln('    platform: ${error.exception.originalError ?? '-'}');
    }

    out.writeln();
  }

  // Written even when empty, and distinguishing empty from absent: "no
  // records", "records were not collected" and a missing section lead a reader
  // to three different conclusions.
  if (renderedLogRecords == null) {
    out.writeln('--- Log records (not collected)');
    out.writeln('No log sink is installed in this build, so no records were '
        'kept. Their absence here says nothing about what happened.');
  } else {
    out.writeln('--- Log records (${renderedLogRecords.length})');
    if (renderedLogRecords.isEmpty) {
      out.writeln('No log records captured.');
    } else {
      out.writeAll(renderedLogRecords.map((line) => '$line\n'));
    }
  }

  // Always written, for the same reason as the log section: a reader cannot
  // tell an omitted section from one with nothing in it.
  out
    ..writeln()
    ..writeln('--- Request pool waits (${concurrencyEvents.length})');
  if (concurrencyEvents.isEmpty) {
    out.writeln('No requests waited for a pool slot.');
  } else {
    // The request pool caps in-flight requests, so a queued request can look
    // slow for reasons that have nothing to do with the server it is calling.
    for (final event in concurrencyEvents) {
      out.writeln('    ${_utc(event.timestamp)} '
          'waited ${event.waitDuration.inMilliseconds}ms '
          '(queue depth ${event.queueDepthAtEnqueue}, '
          'slots in use ${event.slotsInUseAfterAcquire}) '
          '${event.uri}');
    }
  }

  return out.toString();
}

String _utc(DateTime at) => at.toUtc().toIso8601String();
