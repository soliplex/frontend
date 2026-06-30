import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('ServerInfo.fromJson', () {
    test('parses all fields', () {
      final info = ServerInfo.fromJson(const {
        'installation_id': 'soliplex-conf-minimal',
        'name': 'Demo Server',
        'description': 'A friendly demo instance',
      });

      expect(info.installationId, 'soliplex-conf-minimal');
      expect(info.name, 'Demo Server');
      expect(info.description, 'A friendly demo instance');
    });

    test('treats missing name/description as null', () {
      final info = ServerInfo.fromJson(const {
        'installation_id': 'soliplex-conf-minimal',
      });

      expect(info.installationId, 'soliplex-conf-minimal');
      expect(info.name, isNull);
      expect(info.description, isNull);
    });

    test('treats blank/whitespace name/description as null', () {
      final info = ServerInfo.fromJson(const {
        'installation_id': 'soliplex-conf-minimal',
        'name': '',
        'description': '   ',
      });

      expect(info.name, isNull);
      expect(info.description, isNull);
    });

    test('throws when installation_id is missing or not a string', () {
      expect(
        () => ServerInfo.fromJson(const {'name': 'Demo Server'}),
        throwsA(isA<MalformedResponseException>()),
      );
      expect(
        () => ServerInfo.fromJson(const {'installation_id': 42}),
        throwsA(isA<MalformedResponseException>()),
      );
    });
  });

  group('ServerInfo equality', () {
    test('equal when all fields match', () {
      const a = ServerInfo(
        installationId: 'id',
        name: 'Demo',
        description: 'desc',
      );
      const b = ServerInfo(
        installationId: 'id',
        name: 'Demo',
        description: 'desc',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when a field differs', () {
      const a = ServerInfo(installationId: 'id', name: 'Demo');
      const b = ServerInfo(installationId: 'id', name: 'Other');

      expect(a, isNot(equals(b)));
    });
  });
}
