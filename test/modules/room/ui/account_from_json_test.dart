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

    test('uses email as the name but drops the duplicate email line', () {
      final account = accountFromJson({'email': 'ada@example.com'});
      expect(account.name, 'ada@example.com');
      expect(account.email, isNull);
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

    test('treats a whitespace-only preferred_username as absent', () {
      final account = accountFromJson({
        'preferred_username': '  ',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada@example.com');
    });

    test('reports a blank email as null', () {
      final account =
          accountFromJson({'preferred_username': 'ada', 'email': ''});
      expect(account.email, isNull);
    });

    test('treats a whitespace-only email as null', () {
      final account =
          accountFromJson({'preferred_username': 'ada', 'email': '  '});
      expect(account.email, isNull);
    });

    test('treats a non-string field as absent without discarding siblings', () {
      // A malformed claim (here a numeric given_name) must not take down the
      // valid preferred_username and email alongside it.
      final account = accountFromJson({
        'given_name': 123,
        'preferred_username': 'ada',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada');
      expect(account.email, 'ada@example.com');
    });

    test('falls back to "Signed in" when every claim is non-string', () {
      final account = accountFromJson({
        'given_name': 1,
        'family_name': true,
        'preferred_username': ['ada'],
        'email': {'value': 'ada@example.com'},
      });
      expect(account.name, 'Signed in');
      expect(account.email, isNull);
    });
  });
}
