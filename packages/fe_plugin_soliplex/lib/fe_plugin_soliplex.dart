/// MontyPlugin that bridges sandboxed Python to the Soliplex server API.
///
/// Exposes rooms, threads, runs, documents, completions, and uploads as
/// host functions callable from Python.
///
/// ```monty
/// rooms = soliplex_list_rooms()
/// room = soliplex_get_room("my-room")
/// docs = soliplex_get_documents("my-room")
/// response = soliplex_complete("completion-id", messages=[...])
/// ```
library;

export 'src/soliplex_plugin.dart';
