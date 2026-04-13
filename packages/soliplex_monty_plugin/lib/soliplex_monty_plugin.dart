/// MontyPlugin that bridges sandboxed Python to the Soliplex server API.
///
/// Exposes rooms, threads, documents, conversations, and uploads as
/// host functions callable from Python.
///
/// ```monty
/// servers = soliplex_list_servers()
/// rooms = soliplex_list_rooms("my-server")
/// result = soliplex_new_thread("my-server", "my-room", "Hello!")
/// ```
library;

export 'src/monty_script_environment.dart';
export 'src/soliplex_connection.dart';
export 'src/soliplex_plugin.dart';
