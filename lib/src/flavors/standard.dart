import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../core/app_identity.dart';
import '../core/app_module.dart';
import '../core/flavor.dart';
import '../core/inactivity/inactivity_config.dart';
import '../core/shell_config.dart';
import '../core/status_message_config.dart';
import '../modules/auth/consent_notice.dart';
import '../modules/auth/platform/callback_params.dart';
import '../modules/room/document_browser_url.dart';
import 'standard_kit.dart';

/// Builds the standard [Flavor]: the full module set on shared session
/// state, ready to [Flavor.build] — or to compose first.
///
/// This is the customization point ADR-003 blesses: swap [theme] for full
/// color control, or pass [extraModules] to add features (the callback receives
/// the composition kit, so a custom module can share state such as
/// `kit.serverManager`). Mapping the kit's fields onto the [Flavor] lives here;
/// [Flavor.build] assembles that [Flavor] into a [ShellConfig] — neither is
/// transcribed at the call site.
Future<Flavor> standardFlavor({
  AppIdentity? identity,
  FlavorTheme theme = const FlavorTheme.brand(BrandTheme.soliplex()),
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Duration inactivityWarningDuration = InactivityConfig.defaultWarningDuration,
  Duration inactivityGraceDuration = InactivityConfig.defaultGraceDuration,
  bool enableDocumentFilter = true,
  String statusMessageFilePath = StatusMessageConfig.defaultFilePath,
  Duration statusMessagePollInterval = StatusMessageConfig.defaultPollInterval,
  DocumentBrowserUrlResolver? documentBrowserUrl,
  List<AppModule> Function(StandardKit kit)? extraModules,
}) async {
  final effectiveIdentity = identity ?? AppIdentity.soliplex;
  final kit = await buildStandardKit(
    identity: effectiveIdentity,
    redirectScheme: redirectScheme,
    defaultBackendUrl: defaultBackendUrl,
    callbackParams: callbackParams,
    consentNotice: consentNotice,
    inactivityWarningDuration: inactivityWarningDuration,
    inactivityGraceDuration: inactivityGraceDuration,
    enableDocumentFilter: enableDocumentFilter,
    statusMessageFilePath: statusMessageFilePath,
    statusMessagePollInterval: statusMessagePollInterval,
  );
  return Flavor(
    identity: effectiveIdentity,
    theme: theme,
    modules: [
      ...kit.modules,
      if (documentBrowserUrl != null)
        DocumentBrowserUrlModule(documentBrowserUrl),
      ...?extraModules?.call(kit),
    ],
    initialRoute: kit.initialRoute,
    refreshListenable: kit.refreshListenable,
    inactivity: kit.inactivity,
    statusMessage: kit.statusMessage,
  );
}

/// The opinionated default: the standard [Flavor], lowered. Customization
/// beyond a [BrandTheme] goes through [standardFlavor].
Future<ShellConfig> standard({
  AppIdentity? identity,
  BrandTheme theme = const BrandTheme.soliplex(),
  // Markings don't flip with brightness — the same instance feeds both themes.
  // Omitted → the design system's neutral built-in (no pills). This is the
  // adopter's configuration point for deployment vocabularies.
  ClassificationTheme? classifications,
  FontResolver fontResolver = const BundledFontResolver(),
  ThemeMode themeMode = ThemeMode.system,
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  Duration inactivityWarningDuration = InactivityConfig.defaultWarningDuration,
  Duration inactivityGraceDuration = InactivityConfig.defaultGraceDuration,
  String statusMessageFilePath = StatusMessageConfig.defaultFilePath,
  Duration statusMessagePollInterval = StatusMessageConfig.defaultPollInterval,
  DocumentBrowserUrlResolver? documentBrowserUrl,
}) async {
  final flavor = await standardFlavor(
    identity: identity,
    theme: FlavorTheme.brand(
      theme,
      fontResolver: fontResolver,
      classifications: classifications,
      mode: themeMode,
    ),
    redirectScheme: redirectScheme,
    defaultBackendUrl: defaultBackendUrl,
    callbackParams: callbackParams,
    consentNotice: consentNotice,
    inactivityWarningDuration: inactivityWarningDuration,
    inactivityGraceDuration: inactivityGraceDuration,
    statusMessageFilePath: statusMessageFilePath,
    statusMessagePollInterval: statusMessagePollInterval,
    documentBrowserUrl: documentBrowserUrl,
  );
  return flavor.build();
}
