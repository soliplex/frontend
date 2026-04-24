import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent_monty/src/monty_extension_set.dart';

/// Scaffold for the `dart_monty` bridge extension.
///
/// The full implementation (lifecycle, observation fan-out, the
/// `run_python_on_device` [ClientTool]) lands in the follow-up PR. This
/// scaffold exists so the package is self-contained and the wiring PR
/// can start importing the type.
class MontyRuntimeExtension extends SessionExtension {
  MontyRuntimeExtension({required MontyExtensionSet extensions})
      : _extensions = extensions;

  // Preserved for the implementation PR — suppresses unused-field lint
  // without code-gen noise.
  // ignore: unused_field
  final MontyExtensionSet _extensions;

  @override
  String get namespace => 'monty';

  @override
  int get priority => 0;

  @override
  List<ClientTool> get tools => const [];

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void onDispose() {}
}
