import 'package:meta/meta.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';

/// Human-readable identity for a Soliplex server, from
/// `GET /api/v1/installation/identity`.
///
/// Lets frontends show a friendly name and description in place of the raw
/// server address. The backend responds 404 when neither field is configured,
/// so this is always optional metadata — callers must fall back to the raw
/// address when it is absent.
@immutable
class ServerInfo {
  /// Creates server identity metadata.
  const ServerInfo({
    required this.installationId,
    this.name,
    this.description,
  });

  /// Parses a `GET /api/v1/installation/identity` response body.
  ///
  /// Blank or whitespace-only `name`/`description` are treated as absent so the
  /// `null` fallback contract holds for every display site. Throws
  /// [MalformedResponseException] when `installation_id` is missing or not a
  /// string.
  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final id = json['installation_id'];
    if (id is! String) {
      throw const MalformedResponseException(
        message: 'identity response missing string installation_id',
      );
    }
    return ServerInfo(
      installationId: id,
      name: _blankToNull(json['name']),
      description: _blankToNull(json['description']),
    );
  }

  /// The server's installation identifier.
  final String installationId;

  /// Human-readable server name (e.g., "Demo Server"), if configured.
  final String? name;

  /// Brief server description, if configured.
  final String? description;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerInfo &&
        other.installationId == installationId &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(installationId, name, description);

  @override
  String toString() =>
      'ServerInfo(installationId: $installationId, name: $name)';
}

String? _blankToNull(Object? value) {
  final text = value as String?;
  if (text == null || text.trim().isEmpty) return null;
  return text;
}
