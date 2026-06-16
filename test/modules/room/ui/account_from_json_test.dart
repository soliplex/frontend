import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';

void main() {
  group('accountFromJson', () {
    test('prefers the full name from given + family', () {
      final account = accountFromJson({
        'given_name': 'Ada',
        'family_name': 'Lovelace',
        'preferred_username': 'ada',
        'email': 'ada@example.com',
      });
      expect(account.name, 'Ada Lovelace');
      expect(account.email, 'ada@example.com');
    });

    test('uses a lone given (or family) name, trimmed', () {
      final account = accountFromJson({'given_name': 'Ada', 'family_name': ''});
      expect(account.name, 'Ada');
      expect(account.email, isNull);
    });

    test('falls back to preferred_username when no name is present', () {
      final account = accountFromJson({
        'preferred_username': 'ada',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada');
    });

    test('falls back to email when only an email is present', () {
      final account = accountFromJson({'email': 'ada@example.com'});
      expect(account.name, 'ada@example.com');
      expect(account.email, 'ada@example.com');
    });

    test('falls back to "Signed in" when the payload carries no label', () {
      final account = accountFromJson(const {});
      expect(account.name, 'Signed in');
      expect(account.email, isNull);
    });

    test('treats whitespace-only name fields as absent', () {
      final account = accountFromJson({
        'given_name': '  ',
        'family_name': '',
        'preferred_username': 'ada',
      });
      expect(account.name, 'ada');
    });

    test('reports a blank email as null', () {
      final account =
          accountFromJson({'preferred_username': 'ada', 'email': ''});
      expect(account.email, isNull);
    });
  });
}
