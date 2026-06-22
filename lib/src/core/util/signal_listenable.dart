import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Bridges a [ReadonlySignal] to Flutter's [ChangeNotifier] / [Listenable].
///
/// Use with GoRouter's `refreshListenable` to trigger re-evaluation
/// when signal values change.
class SignalListenable extends ChangeNotifier {
  SignalListenable(ReadonlySignal<Object?> signal) {
    _unsubscribe = signal.subscribe((_) => notifyListeners());
  }

  late final void Function() _unsubscribe;

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
