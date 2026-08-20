import 'package:soliplex_logging/soliplex_logging.dart';

/// Renders a [LogRecord] as one plain-text line for the diagnostics screen,
/// and optionally with its stack trace across following lines for the exported
/// report.
///
/// The package's own `formatLogMessage` drops `attributes` and `error`, which
/// are exactly where diagnostic detail lives — a probe failure carries the
/// resolved host, the platform error code, and the elapsed time as attributes.
/// It is not strictly lossier, though: it emits `traceId`/`spanId`, which this
/// drops in favour of the timestamp, since a report is read as a timeline.
///
/// The timestamp is written in UTC so a record lines up against server logs
/// read on another machine.
///
/// Set [includeStackTrace] for the report, where an unexpected error's frames
/// name where it came from. The screen leaves it off: one record per row keeps
/// the list scannable.
String formatLogRecord(LogRecord record, {bool includeStackTrace = false}) {
  final out = StringBuffer()
    ..write(record.timestamp.toUtc().toIso8601String())
    ..write(' [${record.level.label}] ')
    ..write('${_singleLine(record.loggerName)}: ')
    // The exported report is one text blob, so a record there is delimited by
    // starting at column 0 — only the indented stack-trace continuation below
    // is meant to add lines. An embedded break in the message, an attribute or
    // the error would forge a record that never happened. (The on-screen list
    // is not parsed, one row per record, so this only matters for the report.)
    ..write(_singleLine(record.message));

  if (record.attributes.isNotEmpty) {
    final pairs = record.attributes.entries
        .map((e) => '${_singleLine(e.key)}=${_singleLine('${e.value}')}')
        .join(', ');
    out.write(' {$pairs}');
  }

  if (record.error != null) {
    out.write(' | error: ${_singleLine('${record.error}')}');
  }

  if (includeStackTrace && record.stackTrace != null) {
    for (final frame in '${record.stackTrace}'.trimRight().split('\n')) {
      out.write('\n    $frame');
    }
  }

  return out.toString();
}

/// Collapses the characters a reader, a terminal or a line-splitting parser
/// would treat as a break: CR and LF, the vertical tab and form feed a
/// terminal moves down on, NEL, the ASCII separators, and the Unicode line and
/// paragraph separators.
///
/// A bare `\r` is the dangerous one: it leaves the text intact for `grep`
/// while painting the record's tail over its own timestamp.
String _singleLine(String value) => value.replaceAll(
    RegExp(r'[\r\n\v\f\u0085\u001c-\u001e\u2028\u2029]+'), ' ');
