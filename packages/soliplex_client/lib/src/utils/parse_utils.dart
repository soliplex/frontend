/// Resilient readers for a single field of a JSON map, shared by the
/// backend-schema parsers.
///
/// Each reader isolates a malformed field to itself: an optional field
/// degrades to `null` / empty (logged) rather than throwing, so one bad
/// field never takes down an otherwise-valid object. A required field
/// throws [MalformedResponseException] so the caller can drop just the
/// enclosing entry (its siblings parse independently). An absent field is
/// always normal and silent.
library;

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_client.parse_utils');

void _logDropped(String message) => _logger.warning(message);

/// A required string field: throws [MalformedResponseException] when absent
/// or not a string.
String requireString(Object? value, String field) {
  if (value is String) return value;
  throw MalformedResponseException(
    message: 'field "$field" must be a string, got ${value.runtimeType}',
  );
}

/// An optional string field: a present-but-wrong-typed value degrades to null
/// (logged). An absent field is normal and silent.
String? stringOrNull(Object? value, String field) {
  if (value == null || value is String) return value as String?;
  _logDropped(
    'field "$field": expected string, got ${value.runtimeType}; dropped.',
  );
  return null;
}

/// An optional int field: a present-but-wrong-typed value degrades to null
/// (logged). An absent field is normal and silent.
int? intOrNull(Object? value, String field) {
  if (value == null || value is int) return value as int?;
  _logDropped(
    'field "$field": expected int, got ${value.runtimeType}; dropped.',
  );
  return null;
}

/// An optional list-of-strings field: a present-but-non-list degrades to empty
/// and any non-string element is dropped. Both cases are logged; an absent
/// field is normal and silent.
List<String> stringList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    _logDropped(
      'field "$field": expected list, got ${value.runtimeType}; using empty.',
    );
    return const [];
  }
  final result = value.whereType<String>().toList();
  if (result.length != value.length) {
    _logDropped('field "$field": dropped '
        '${value.length - result.length} non-string element(s).');
  }
  return result;
}

/// An optional list-of-ints field: a present-but-non-list degrades to empty and
/// any non-int element is dropped. Both cases are logged; an absent field is
/// normal and silent.
List<int> intList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    _logDropped(
      'field "$field": expected list, got ${value.runtimeType}; using empty.',
    );
    return const [];
  }
  final result = value.whereType<int>().toList();
  if (result.length != value.length) {
    _logDropped('field "$field": dropped '
        '${value.length - result.length} non-int element(s).');
  }
  return result;
}

/// Reads a raw JSON value into a string→string map, dropping (and logging) any
/// non-string key or value. An absent field is normal and silent.
Map<String, String> stringMap(Object? value, String field) {
  if (value is! Map) {
    if (value != null) {
      _logDropped(
        'field "$field": expected map, got ${value.runtimeType}; using empty.',
      );
    }
    return const {};
  }
  final out = <String, String>{};
  value.forEach((key, mapValue) {
    if (key is String && mapValue is String) out[key] = mapValue;
  });
  final dropped = value.length - out.length;
  if (dropped != 0) {
    _logDropped('field "$field": dropped $dropped '
        'non-string entr${dropped == 1 ? 'y' : 'ies'}.');
  }
  return out;
}
