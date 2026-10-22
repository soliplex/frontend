import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/preferences/bandwidth_preference.dart';
import 'package:soliplex_frontend/src/modules/preferences/preferences_module.dart';

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BandwidthPreference preference;
  late ServerManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preference = BandwidthPreference();
    await preference.setLowBandwidth(true);
    manager = ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );
  });

  PreferencesAppModule module() => PreferencesAppModule(
        appName: 'Acme',
        preference: preference,
        serverManager: manager,
      );

  void addServer() => manager.addServer(
        serverId: 'https://a.example',
        serverUrl: Uri.parse('https://a.example'),
        requiresAuth: false,
      );

  test('looks up the servers that are added while the mode is on', () async {
    final preferences = module();
    addTearDown(preferences.onDispose);

    addServer();

    expect(preference.checkingServers.value, contains('https://a.example'));
  });

  test('disposing it stops looking servers up', () async {
    await module().onDispose();

    addServer();

    expect(preference.checkingServers.value, isEmpty);
  });
}
