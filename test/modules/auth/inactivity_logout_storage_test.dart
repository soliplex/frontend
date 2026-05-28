import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsInactivityLogoutFlagStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('isMarked returns false when the flag was never set', () async {
      final storage = SharedPrefsInactivityLogoutFlagStorage();

      expect(await storage.isMarked('server-a'), isFalse);
    });

    test('mark sets the flag so isMarked returns true', () async {
      final storage = SharedPrefsInactivityLogoutFlagStorage();

      await storage.mark('server-a');

      expect(await storage.isMarked('server-a'), isTrue);
    });

    test('isMarked does not clear the flag', () async {
      final storage = SharedPrefsInactivityLogoutFlagStorage();

      await storage.mark('server-a');
      await storage.isMarked('server-a');

      expect(await storage.isMarked('server-a'), isTrue);
    });

    test('clear removes the flag', () async {
      final storage = SharedPrefsInactivityLogoutFlagStorage();

      await storage.mark('server-a');
      await storage.clear('server-a');

      expect(await storage.isMarked('server-a'), isFalse);
    });

    test('flags are scoped per server id', () async {
      final storage = SharedPrefsInactivityLogoutFlagStorage();

      await storage.mark('server-a');

      expect(await storage.isMarked('server-b'), isFalse);
      expect(await storage.isMarked('server-a'), isTrue);
    });
  });
}
