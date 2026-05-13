import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _defaultLogger =
    LogManager.instance.getLogger('soliplex_client.json_patch');

/// Applies RFC 6902 JSON Patch operations to a state map.
///
/// Returns a new map with the patches applied. Failed operations are
/// logged via [logger] (defaults to a `LogManager` logger that flows
/// through configured sinks) and skipped so the rest of the patch can
/// land. Supports `add`, `replace`, and `remove`; `move`, `copy`, and
/// `test` are not implemented and produce a warning log.
Map<String, dynamic> applyJsonPatch(
  Map<String, dynamic> state,
  List<dynamic> operations, {
  Logger? logger,
}) {
  final log = logger ?? _defaultLogger;
  var result = Map<String, dynamic>.from(state);

  for (final op in operations) {
    if (op is! Map<String, dynamic>) {
      _logPatchWarning(log, 'Operation is not a map', op);
      continue;
    }

    final operation = op['op'] as String?;
    final path = op['path'] as String?;
    final value = op['value'];

    if (operation == null || path == null) {
      _logPatchWarning(log, 'Missing op or path', op);
      continue;
    }

    try {
      result = switch (operation) {
        'add' => _setAtPath(result, path, value, insert: true, logger: log),
        'replace' => _setAtPath(result, path, value, logger: log),
        'remove' => _removeAtPath(result, path),
        _ => () {
            _logPatchWarning(log, 'Unsupported operation', op);
            return result;
          }(),
      };
    } catch (e, st) {
      _logPatchWarning(
        log,
        'Failed to apply $operation at $path: $e',
        op,
        stackTrace: st,
      );
    }
  }

  return result;
}

Map<String, dynamic> _setAtPath(
  Map<String, dynamic> state,
  String path,
  dynamic value, {
  required Logger logger,
  bool insert = false,
}) {
  final segments = _parsePath(path);
  if (segments.isEmpty) {
    // Path "/" means replace root - but we always return a map
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    return state;
  }

  final result = _deepCopy(state);
  dynamic current = result;

  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (current is Map<String, dynamic>) {
      if (current[segment] == null) {
        final nextSegment = segments[i + 1];
        final nextIsArrayIndex =
            int.tryParse(nextSegment) != null || nextSegment == '-';
        current[segment] = nextIsArrayIndex ? <dynamic>[] : <String, dynamic>{};
      }
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index != null && index >= 0 && index < current.length) {
        current = current[index];
      } else {
        return result; // Invalid path
      }
    }
  }

  final lastSegment = segments.last;
  if (current is Map<String, dynamic>) {
    current[lastSegment] = value;
  } else if (current is List) {
    // RFC 6902: "-" means append to end of array
    if (lastSegment == '-') {
      current.add(value);
    } else {
      final index = int.tryParse(lastSegment);
      if (index != null) {
        if (insert && index >= 0 && index <= current.length) {
          // RFC 6902 §4.1: add inserts before the index, shifting elements.
          current.insert(index, value);
        } else if (!insert && index >= 0 && index < current.length) {
          current[index] = value;
        } else {
          _logPatchWarning(
            logger,
            'Array index $index out of bounds '
            '(length=${current.length}) at $path',
            {'op': insert ? 'add' : 'replace', 'path': path, 'value': value},
          );
        }
      }
    }
  }

  return result;
}

Map<String, dynamic> _removeAtPath(Map<String, dynamic> state, String path) {
  final segments = _parsePath(path);
  if (segments.isEmpty) return state;

  final result = _deepCopy(state);
  dynamic current = result;

  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (current is Map<String, dynamic>) {
      final next = current[segment];
      if (next == null) return result; // Path doesn't exist
      current = next;
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index != null && index >= 0 && index < current.length) {
        current = current[index];
      } else {
        return result; // Invalid path
      }
    }
  }

  final lastSegment = segments.last;
  if (current is Map<String, dynamic>) {
    current.remove(lastSegment);
  } else if (current is List) {
    final index = int.tryParse(lastSegment);
    if (index != null && index >= 0 && index < current.length) {
      current.removeAt(index);
    }
  }

  return result;
}

List<String> _parsePath(String path) {
  if (path.isEmpty || path == '/') return [];
  return path.split('/').where((s) => s.isNotEmpty).toList();
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> map) {
  return map.map((key, value) {
    if (value is Map<String, dynamic>) {
      return MapEntry(key, _deepCopy(value));
    } else if (value is List) {
      return MapEntry(key, _deepCopyList(value));
    }
    return MapEntry(key, value);
  });
}

List<dynamic> _deepCopyList(List<dynamic> list) {
  return list.map((item) {
    if (item is Map<String, dynamic>) {
      return _deepCopy(item);
    } else if (item is List) {
      return _deepCopyList(item);
    }
    return item;
  }).toList();
}

void _logPatchWarning(
  Logger logger,
  String message,
  dynamic operation, {
  StackTrace? stackTrace,
}) {
  logger.warning(
    '$message: $operation',
    stackTrace: stackTrace,
    attributes: {'operation': operation.toString()},
  );
}
