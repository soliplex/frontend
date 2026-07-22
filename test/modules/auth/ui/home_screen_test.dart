import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/connection_probe.dart';
import 'package:soliplex_frontend/src/modules/auth/consent_notice.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/connect_flow_rail.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/home_screen.dart';
import 'package:soliplex_frontend/src/shared/markdown/prose_markdown.dart';
import 'package:soliplex_frontend/version.dart';

import '../../../helpers/fakes.dart';

const _testProvider = AuthProviderConfig(
  id: 'keycloak',
  name: 'Authenticate with Keycloak',
  serverUrl: 'https://sso.example.com/realms/app',
  clientId: 'soliplex',
  scope: 'openid email profile',
);

ServerManager _createServerManager() => ServerManager(
      authFactory: () => AuthSession(
        refreshService: FakeTokenRefreshService(),
      ),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Future<List<AuthProviderConfig>> _noAuthDiscover(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) async =>
    [];

Future<List<AuthProviderConfig>> _failDiscover(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) async {
  throw const NetworkException(message: 'Connection refused');
}

/// Discover that fails HTTPS (network error) but succeeds HTTP with a provider.
Future<List<AuthProviderConfig>> _httpOnlyDiscover(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) async {
  if (serverUrl.scheme == 'https') {
    throw const NetworkException(message: 'Connection refused');
  }
  return [_testProvider];
}

const _secondProvider = AuthProviderConfig(
  id: 'enfold',
  name: 'Authenticate with Enfold',
  serverUrl: 'https://sso.example.com/realms/enfold',
  clientId: 'soliplex',
  scope: 'openid email profile',
);

Future<List<AuthProviderConfig>> _multiProviderDiscover(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) async =>
    [_testProvider, _secondProvider];

Widget _buildApp({
  required ServerManager serverManager,
  String appName = 'Soliplex',
  Widget? logo,
  GoRouter? router,
  FakeAuthFlow? authFlow,
  DiscoverProviders? discover,
  String? defaultBackendUrl,
  String? initialLocation,
  ConsentNotice? consentNotice,
}) {
  final fakeAuthFlow = authFlow ?? FakeAuthFlow();

  router ??= GoRouter(
    initialLocation: initialLocation ?? '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) => HomeScreen(
          serverManager: serverManager,
          appName: appName,
          logo: logo,
          defaultBackendUrl: defaultBackendUrl,
          autoConnectUrl: state.uri.queryParameters['url'],
        ),
      ),
      GoRoute(
        path: '/lobby',
        builder: (_, __) => const Scaffold(
          body: Text('Lobby placeholder'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      serverManagerProvider.overrideWithValue(serverManager),
      authFlowProvider.overrideWithValue(fakeAuthFlow),
      probeClientProvider.overrideWithValue(FakeHttpClient()),
      inactivityLogoutFlagsProvider
          .overrideWithValue(InMemoryInactivityLogoutFlagStorage()),
      discoverProvidersProvider.overrideWithValue(
        discover ?? _noAuthDiscover,
      ),
      if (consentNotice != null)
        consentNoticeProvider.overrideWithValue(consentNotice),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void _loginEntry(ServerEntry entry) {
  entry.auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
    ),
    tokens: AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('HomeScreen connection form', () {
    testWidgets('shows URL input and connect button when no servers',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Soliplex'), findsOneWidget);
      expect(
        find.text('Connect to a Soliplex server'),
        findsOneWidget,
      );
    });

    testWidgets('shows custom app name', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        appName: 'MyApp',
      ));
      await tester.pumpAndSettle();

      expect(find.text('MyApp'), findsOneWidget);
      expect(find.text('Soliplex'), findsNothing);
    });

    testWidgets('shows the library version in the top bar', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text(soliplexVersion), findsOneWidget);
    });

    testWidgets('hides the flow rail on narrow viewports', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // Default test viewport (800px) is below the desktop breakpoint.
      expect(find.byType(ConnectFlowRail), findsNothing);
    });

    testWidgets('shows the flow rail on wide viewports', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectFlowRail), findsOneWidget);
      // On the URL-input state, the URL node is current.
      expect(find.text(ConnectStep.url.label), findsOneWidget);
    });

    testWidgets('shows logo when provided', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        logo: const Icon(Icons.star, key: Key('test-logo')),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('test-logo')), findsOneWidget);
    });

    testWidgets('shows fallback icon when no logo provided', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    });

    testWidgets('probes connection and adds server on submit', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _noAuthDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(serverManager.servers.value, isNotEmpty);
    });

    testWidgets('navigates to lobby when server already exists',
        (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'https://api.example.com',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Should go to lobby, not provider selection.
      expect(find.text('Lobby placeholder'), findsOneWidget);
      expect(
        find.text('Choose how you want to authenticate.'),
        findsNothing,
      );
    });

    testWidgets('different ports are treated as different servers',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'http://localhost:8000',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _noAuthDiscover,
      ));
      await tester.pumpAndSettle();

      // Connect to a different port on the same host (HTTP → insecure warning).
      await tester.enterText(
          find.byType(TextFormField), 'http://localhost:9000');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump();

      // Accept the insecure warning.
      await tester.tap(find.text('Connect anyway'));
      await tester.pumpAndSettle();

      // Should add a second server, not reuse the first.
      expect(serverManager.servers.value, hasLength(2));
    });

    testWidgets('shows network error message on connection failure',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _failDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Cannot reach'), findsOneWidget);
    });

    testWidgets('shows timeout error message', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: (_, __) async {
          throw const NetworkException(message: 'timed out', isTimeout: true);
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('timed out'), findsOneWidget);
    });

    testWidgets('shows server error message for 500', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: (_, __) async {
          throw const ApiException(
              statusCode: 500, message: 'Internal Server Error');
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
      expect(find.textContaining('500'), findsOneWidget);
    });

    testWidgets('shows not found error message for 404', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: (_, __) async {
          throw const NotFoundException(message: 'Not Found');
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not found'), findsOneWidget);
      expect(find.textContaining('incompatible'), findsOneWidget);
    });

    testWidgets('shows insecure warning dialog for HTTP', (tester) async {
      final serverManager = _createServerManager();
      final authFlow = FakeAuthFlow()
        ..nextResult = AuthResult(
          accessToken: 'access',
          refreshToken: 'refresh',
          idToken: 'id',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        discover: _httpOnlyDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'api.example.com');
      await tester.tap(find.text('Connect'));
      // Use pump() — pumpAndSettle times out due to the loading spinner.
      await tester.pump();
      await tester.pump();

      // Inline insecure warning
      expect(
        find.text('This connection is not encrypted'),
        findsOneWidget,
      );
      expect(find.textContaining('not encrypted'), findsOneWidget);
    });

    testWidgets('validates empty URL input', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // Tap Connect with empty input
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Server address is required'), findsOneWidget);
    });

    testWidgets('validates URL with whitespace', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'api example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text("Can't contain whitespaces"), findsOneWidget);
    });

    testWidgets('validates URL with invalid scheme', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'ftp://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
        find.text('Only http and https are supported'),
        findsOneWidget,
      );
    });

    testWidgets('shows the sign-in heading on provider selection phase',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to api.example.com'), findsOneWidget);
      expect(find.text('Connect to a Soliplex server'), findsNothing);
    });

    testWidgets('shows "Change server" button on provider selection phase',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Change server'), findsOneWidget);

      // Tapping it returns to URL input.
      await tester.tap(find.text('Change server'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Connect to a Soliplex server'), findsOneWidget);
    });

    testWidgets('hides server section on provider selection phase',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'existing',
        serverUrl: Uri.parse('https://existing.example.com'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      // Server section visible on URL input phase.
      expect(find.text('Your servers'), findsOneWidget);

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Server section hidden on provider selection phase.
      expect(find.text('Your servers'), findsNothing);
    });

    testWidgets('resets to URL input after successful authentication',
        (tester) async {
      final serverManager = _createServerManager();
      final authFlow = FakeAuthFlow()
        ..nextResult = AuthResult(
          accessToken: 'access',
          refreshToken: 'refresh',
          idToken: 'id',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      // Connect — multiple providers, so we get provider selection phase.
      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose how you want to authenticate.'),
        findsOneWidget,
      );

      // Pick a provider to authenticate.
      await tester.tap(find.text('Authenticate with Keycloak'));
      await tester.pumpAndSettle();

      // Should navigate to lobby.
      expect(find.text('Lobby placeholder'), findsOneWidget);
    });

    testWidgets('saves pre-auth state before web redirect', (tester) async {
      final serverManager = _createServerManager();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        discover: _multiProviderDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Pick a provider — triggers authenticate → AuthRedirectInitiated.
      await tester.tap(find.text('Authenticate with Keycloak'));
      await tester.pump();
      await tester.pump();

      // Pre-auth state should have been saved before the redirect.
      final preAuth = await PreAuthStateStorage.load();
      expect(preAuth, isNotNull);
      expect(preAuth!.providerId, 'keycloak');
      expect(preAuth.clientId, 'soliplex');
      expect(
        preAuth.discoveryUrl,
        'https://sso.example.com/realms/app/.well-known/openid-configuration',
      );
    });
  });

  group('HomeScreen server section', () {
    testWidgets('shows server section with logged-out servers below form',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // Connection form still visible.
      expect(find.text('Connect'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);

      // Server section visible.
      expect(find.text('Your servers'), findsOneWidget);
      expect(find.text('https://api.example.com'), findsOneWidget);
    });

    testWidgets('hides connected servers from list', (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // Server section heading shown (server exists).
      expect(find.text('Your servers'), findsOneWidget);
      // But the server itself is not listed (it's connected).
      expect(find.text('https://api.example.com'), findsNothing);
    });

    testWidgets('shows Go to Lobby when authenticated servers exist',
        (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Go to Lobby'), findsOneWidget);
    });

    testWidgets('tapping logged-out server connects and navigates to lobby',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'staging',
        serverUrl: Uri.parse('https://staging.example.com'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _noAuthDiscover,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('https://staging.example.com'));
      await tester.pumpAndSettle();

      expect(find.text('Lobby placeholder'), findsOneWidget);
    });

    testWidgets('collapses after 5 entries with show-more button',
        (tester) async {
      final serverManager = _createServerManager();
      for (var i = 0; i < 7; i++) {
        serverManager.addServer(
          serverId: 'server$i',
          serverUrl: Uri.parse('https://server$i.example.com'),
        );
      }

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // First 5 visible.
      for (var i = 0; i < 5; i++) {
        expect(find.text('https://server$i.example.com'), findsOneWidget);
      }
      // 6th and 7th hidden.
      expect(find.text('https://server5.example.com'), findsNothing);
      expect(find.text('https://server6.example.com'), findsNothing);

      // Show more button.
      expect(find.text('Show 2 more'), findsOneWidget);

      // Scroll to the button and tap.
      await tester.ensureVisible(find.text('Show 2 more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show 2 more'));
      await tester.pumpAndSettle();

      // All visible now (scroll to bottom to verify last entries).
      await tester.ensureVisible(find.text('https://server6.example.com'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 7; i++) {
        expect(find.text('https://server$i.example.com'), findsOneWidget);
      }
      expect(find.text('Show 2 more'), findsNothing);
    });

    testWidgets('delete button removes server after confirmation',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsOneWidget);

      // Tapping delete asks first; the server is still there.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Remove server?'), findsOneWidget);
      expect(find.text('https://api.example.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(SoliplexButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsNothing);
      // Section heading also gone since no servers remain.
      expect(find.text('Your servers'), findsNothing);
    });

    testWidgets('delete button keeps server when confirmation is cancelled',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SoliplexButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(serverManager.servers.value.containsKey('test'), isTrue);
      expect(find.text('https://api.example.com'), findsOneWidget);
    });

    testWidgets('updates when server is added externally', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsNothing);

      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsOneWidget);
    });

    testWidgets('no-auth server is hidden from logged-out list',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // Server section heading shown (server exists).
      expect(find.text('Your servers'), findsOneWidget);
      // But the no-auth server is not listed (it's connected).
      expect(find.text('http://localhost:8000'), findsNothing);
    });

    testWidgets('no-auth server counts as connected', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      // A no-auth server is connected, so the section offers "Go to Lobby".
      expect(find.text('Go to Lobby'), findsOneWidget);
    });

    testWidgets('keystroke refocuses URL field when unfocused', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      final editableText = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(EditableText),
        ),
      );
      final focusNode = editableText.focusNode;

      // Should have autofocus.
      expect(focusNode.hasFocus, isTrue);

      // Unfocus the text field.
      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isFalse);

      // Press a key — should refocus the text field.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('no server section when no servers exist', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Your servers'), findsNothing);
    });

    testWidgets('pre-populates URL field from defaultBackendUrl',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        defaultBackendUrl: 'https://api.example.com',
      ));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, 'https://api.example.com');
    });

    testWidgets('does not pre-populate URL when servers exist', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'existing',
        serverUrl: Uri.parse('https://existing.example.com'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        defaultBackendUrl: 'https://api.example.com',
      ));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('autoConnectUrl sets URL and triggers connect', (tester) async {
      final serverManager = _createServerManager();
      final encodedUrl = Uri.encodeComponent('https://api.example.com');

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _noAuthDiscover,
        initialLocation: '/?url=$encodedUrl',
      ));
      await tester.pumpAndSettle();

      // Should have auto-connected and navigated to lobby.
      expect(find.text('Lobby placeholder'), findsOneWidget);
    });

    testWidgets('autoConnectUrl takes precedence over defaultBackendUrl',
        (tester) async {
      final serverManager = _createServerManager();
      final encodedUrl = Uri.encodeComponent('https://auto.example.com');

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _noAuthDiscover,
        defaultBackendUrl: 'https://default.example.com',
        initialLocation: '/?url=$encodedUrl',
      ));
      await tester.pumpAndSettle();

      // Should auto-connect to the autoConnectUrl, not defaultBackendUrl.
      expect(
          serverManager.servers.value.containsKey('https://auto.example.com'),
          isTrue);
    });

    testWidgets('re-fills URL field when last server is removed',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        defaultBackendUrl: 'http://localhost:8000',
      ));
      await tester.pumpAndSettle();

      // Field is empty because servers exist.
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, isEmpty);

      // Remove the server.
      serverManager.removeServer('test');
      await tester.pumpAndSettle();

      // Field should be re-filled with defaultBackendUrl.
      expect(field.controller!.text, 'http://localhost:8000');
    });

    testWidgets('defaultBackendUrl still works without autoConnectUrl',
        (tester) async {
      final serverManager = _createServerManager();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        defaultBackendUrl: 'https://api.example.com',
      ));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, 'https://api.example.com');
    });
  });

  group('HomeScreen consent gate', () {
    const notice = ConsentNotice(
      title: 'Usage notice',
      body: 'You agree to the terms.',
      acknowledgmentLabel: 'Agree & continue',
    );

    Future<void> reachConsent(WidgetTester tester) async {
      await tester.enterText(
          find.byType(TextFormField), 'https://api.example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
    }

    testWidgets('a server with a consent notice lands on the consent gate',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
        consentNotice: notice,
      ));
      await tester.pumpAndSettle();

      await reachConsent(tester);

      expect(find.text('Before you connect'), findsOneWidget);
      expect(find.text('Usage notice'), findsOneWidget);
      expect(find.text('You agree to the terms.'), findsOneWidget);
    });

    testWidgets('renders the notice body as markdown, not a bare Text',
        (tester) async {
      const markdownNotice = ConsentNotice(
        title: 'Usage notice',
        body: 'Agree to the **terms** and the [policy](https://example.com).',
        acknowledgmentLabel: 'Agree & continue',
      );
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
        consentNotice: markdownNotice,
      ));
      await tester.pumpAndSettle();

      await reachConsent(tester);

      final prose = tester.widget<ProseMarkdown>(find.byType(ProseMarkdown));
      expect(prose.data, markdownNotice.body);
      // Markup is parsed away — a bare Text(notice.body) would still show it.
      expect(find.textContaining('**terms**'), findsNothing);
    });

    testWidgets('continue is gated until the agreement box is ticked',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
        consentNotice: notice,
      ));
      await tester.pumpAndSettle();

      await reachConsent(tester);

      // Unticked: tapping the acknowledge button does nothing.
      await tester.tap(find.text('Agree & continue'));
      await tester.pumpAndSettle();
      expect(find.text('Before you connect'), findsOneWidget);

      // Tick the box, then the button advances to provider selection.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree & continue'));
      await tester.pumpAndSettle();

      expect(find.text('Choose how you want to authenticate.'), findsOneWidget);
      expect(find.text('Before you connect'), findsNothing);
    });

    testWidgets('tapping the label text ticks the agreement gate',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
        consentNotice: notice,
      ));
      await tester.pumpAndSettle();

      await reachConsent(tester);

      // Tap the label text, not the checkbox box itself.
      await tester.tap(find.text('I understand and agree to the usage terms.'));
      await tester.pumpAndSettle();

      // The box is now ticked and the gate opens.
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.text('Agree & continue'));
      await tester.pumpAndSettle();

      expect(find.text('Choose how you want to authenticate.'), findsOneWidget);
    });

    testWidgets('leaving and re-entering consent re-arms the gate',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        discover: _multiProviderDiscover,
        consentNotice: notice,
      ));
      await tester.pumpAndSettle();

      await reachConsent(tester);

      // Tick the box, then back out of consent.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // Re-enter consent: the box starts unticked again, and the gate is
      // closed — tapping continue leaves us on the consent screen.
      await reachConsent(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      await tester.tap(find.text('Agree & continue'));
      await tester.pumpAndSettle();
      expect(find.text('Before you connect'), findsOneWidget);
    });
  });
}
