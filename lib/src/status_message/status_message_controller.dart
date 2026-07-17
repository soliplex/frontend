import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/status_message_config.dart';
import 'status_message.dart';
import 'status_message_fetcher.dart';

class StatusMessageController with WidgetsBindingObserver {
  StatusMessageController({
    required StatusMessageFetcher fetcher,
    required this.config,
  }) : _fetcher = fetcher;

  final StatusMessageFetcher _fetcher;
  final StatusMessageConfig config;

  final Signal<StatusMessage?> _message = Signal<StatusMessage?>(null);
  ReadonlySignal<StatusMessage?> get message => _message;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || !config.isEnabled) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_fetch());
    _timer = Timer.periodic(config.pollInterval, (_) => unawaited(_fetch()));
  }

  Future<void> _fetch() async {
    final message = await _fetcher();
    // The banner (keyed by server URL) can dispose this controller while a
    // fetch is in flight — e.g. switching servers or navigating away. Writing a
    // disposed signal throws, so bail before the assignment.
    if (_disposed) return;
    _message.value = message;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_fetch());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _message.dispose();
  }
}
