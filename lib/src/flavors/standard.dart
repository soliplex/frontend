import 'package:flutter/material.dart';

import '../core/app_identity.dart';
import '../core/inactivity/inactivity_config.dart';
import '../core/shell_config.dart';
import 'package:soliplex_design/soliplex_design.dart';
import '../modules/auth/consent_notice.dart';
import '../modules/auth/platform/callback_params.dart';
import '../composition/standard_modules.dart';

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
}) async {
  final effectiveIdentity = identity ?? AppIdentity.soliplex;
  final standardModules = await buildStandardModules(
    identity: effectiveIdentity,
    redirectScheme: redirectScheme,
    defaultBackendUrl: defaultBackendUrl,
    callbackParams: callbackParams,
    consentNotice: consentNotice,
    inactivityWarningDuration: inactivityWarningDuration,
    inactivityGraceDuration: inactivityGraceDuration,
  );
  final lightTheme = lowerBrandTheme(
    theme,
    Brightness.light,
    fontResolver: fontResolver,
    classifications: classifications,
  );
  final darkTheme = lowerBrandTheme(
    theme,
    Brightness.dark,
    fontResolver: fontResolver,
    classifications: classifications,
  );
  return ShellConfig.fromModules(
    appName: effectiveIdentity.appName,
    lightTheme: lightTheme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    initialRoute: standardModules.initialRoute,
    refreshListenable: standardModules.refreshListenable,
    inactivity: standardModules.inactivity,
    modules: standardModules.modules,
  );
}
