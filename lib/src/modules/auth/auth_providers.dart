import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import 'connection_probe.dart';
import 'consent_notice.dart';
import 'platform/auth_flow.dart';
import 'platform/callback_params.dart';
import 'server_manager.dart';

// Required — must be overridden by authModule.

final serverManagerProvider = Provider<ServerManager>(
  (_) => throw UnimplementedError('must be overridden by authModule'),
);

final authFlowProvider = Provider<AuthFlow>(
  (_) => throw UnimplementedError('must be overridden by authModule'),
);

final probeClientProvider = Provider<SoliplexHttpClient>(
  (_) => throw UnimplementedError('must be overridden by authModule'),
);

/// Default [DiscoverProviders] adapter. Bridges the positional-param
/// typedef shape used by callers to the named-param signature exposed by
/// `discoverAuthProviders`.
Future<List<AuthProviderConfig>> _defaultDiscoverProviders(
  Uri serverUrl,
  SoliplexHttpClient httpClient,
) => discoverAuthProviders(serverUrl: serverUrl, httpClient: httpClient);

final discoverProvidersProvider = Provider((_) => _defaultDiscoverProviders);

// Optional — have sensible defaults.

final callbackParamsProvider = Provider<CallbackParams>(
  (_) => const NoCallbackParams(),
);

final consentNoticeProvider = Provider<ConsentNotice?>((_) => null);
