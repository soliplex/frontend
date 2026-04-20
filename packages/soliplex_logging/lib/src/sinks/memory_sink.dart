import 'dart:async';
import 'dart:collection';

import 'package:soliplex_logging/src/log_record.dart';
import 'package:soliplex_logging/src/log_sink.dart';

/// In-memory circular buffer sink for log records.
///
/// Retains the most recent [maxRecords] entries in chronological order.
/// When the buffer is full, the oldest record is silently overwritten.
///
/// Exposes [records] for snapshot retrieval (e.g., error handlers) and
/// [onRecord] stream for live UI updates (e.g., log viewer).
///
/// Uses a circular buffer internally for O(1) writes and provides O(1)
/// random access via the [records] list view, which is required by
/// `ListView.builder` in the log viewer UI.
class MemorySink implements LogSink {
  /// Creates a memory sink that retains at most [maxRecords] entries.
  MemorySink({this.maxRecords = 2000})
    : assert(maxRecords > 0, 'maxRecords must be positive') {
    _view = _RingBufferView(this);
  }

  /// Maximum number of records retained in the buffer.
  final int maxRecords;

  final _buffer = <LogRecord>[];
  int _head = 0;
  int _count = 0;

  late final _RingBufferView _view;

  final _recordController = StreamController<LogRecord>.broadcast();
  final _clearController = StreamController<void>.broadcast();

  /// Live unmodifiable view of current records (oldest first).
  ///
  /// Returns a lightweight wrapper over the internal circular buffer.
  /// No copy is made. The view always reflects the current buffer state.
  /// Safe to index from `ListView.builder`.
  List<LogRecord> get records => _view;

  /// Stream of new records for live listeners.
  Stream<LogRecord> get onRecord => _recordController.stream;

  /// Stream that emits when [clear] is called.
  ///
  /// UI consumers should listen to both [onRecord] and [onClear] to
  /// stay in sync with the buffer state.
  Stream<void> get onClear => _clearController.stream;

  /// Number of records currently retained.
  int get length => _count;

  @override
  void write(LogRecord record) {
    if (_buffer.length < maxRecords) {
      _buffer.add(record);
      _count++;
    } else {
      _buffer[_head] = record;
      _head = (_head + 1) % maxRecords;
    }
    if (!_recordController.isClosed) {
      _recordController.add(record);
    }
  }

  /// Clears all retained records and notifies [onClear] listeners.
  void clear() {
    _buffer.clear();
    _head = 0;
    _count = 0;
    if (!_clearController.isClosed) {
      _clearController.add(null);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    await _recordController.close();
    await _clearController.close();
  }
}

/// Live unmodifiable list view over a circular buffer.
///
/// Reads state directly from the owning [MemorySink] so that the view
/// always reflects the current buffer contents. Maps logical indices
/// (0 = oldest) to physical buffer positions without copying.
/// Provides O(1) access for `ListView.builder`.
class _RingBufferView with ListMixin<LogRecord> {
  _RingBufferView(this._sink);

  final MemorySink _sink;

  @override
  int get length => _sink._count;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Cannot modify an unmodifiable list');

  @override
  LogRecord operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _sink._buffer[(_sink._head + index) % _sink._buffer.length];
  }

  @override
  void operator []=(int index, LogRecord value) =>
      throw UnsupportedError('Cannot modify an unmodifiable list');
}
