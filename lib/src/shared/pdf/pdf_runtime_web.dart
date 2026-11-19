import 'dart:ui_web' as ui_web;

import 'package:pdfrx/pdfrx.dart';

/// Points pdfrx at its PDFium WebAssembly module, once.
///
/// pdfrx resolves its default module path against the page's `<base href>`,
/// but a cache-busted build (`scripts/post-build-cache-bust.sh`) moves every
/// asset under the release hash and tells only Flutter's loader. Asking
/// Flutter's asset manager for the URL follows whichever layout the build
/// has, so the module loads from where the build put it rather than a path
/// the server answers with `index.html`.
void ensurePdfRuntime() {
  Pdfrx.pdfiumWasmModulesUrl ??=
      ui_web.assetManager.getAssetUrl('packages/pdfrx/assets/');
}
