import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_module.dart';

/// Derives a document's clickable browser URL from its `documentUri`.
typedef DocumentBrowserUrlResolver = Uri? Function(String documentUri);

/// TEMPORARY stopgap. Citations and the chunk-visualization page cannot read
/// the backend `source_url` yet — search hits, `Citation`, and the
/// chunk-visualization response all omit document metadata — so a deployment
/// supplies a resolver that derives the browser link from the document's
/// `documentUri`. The default resolves nothing, so the standard build shows no
/// link on those surfaces. (Document listing and the document filter do NOT use
/// this — they read `RagDocument.sourceUrl` directly.)
///
/// A deployment injects its rule through `standard(documentBrowserUrl: ...)` or
/// `standardFlavor(documentBrowserUrl: ...)`; the concrete URL rule lives in the
/// deployment, never here.
///
/// DELETE THIS SEAM once the backend carries `source_url` on citation payloads
/// AND the chunk-visualization response. Remove: this provider, the
/// [DocumentBrowserUrlModule], the `documentBrowserUrl` params on `standard` /
/// `standardFlavor`, and the call sites in `citations_section.dart` and
/// `chunk_visualization_page.dart` — those surfaces then read the field like
/// the document listing / filter already do.
final documentBrowserUrlResolverProvider =
    Provider<DocumentBrowserUrlResolver>((_) => (_) => null);

/// TEMPORARY. Installs [resolver] as the app-wide
/// [documentBrowserUrlResolverProvider] override. Added by `standardFlavor`
/// when a `documentBrowserUrl` is supplied; delete alongside the provider
/// (see above).
class DocumentBrowserUrlModule extends AppModule {
  DocumentBrowserUrlModule(this.resolver);

  final DocumentBrowserUrlResolver resolver;

  @override
  String get namespace => 'document_browser_url';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [
          documentBrowserUrlResolverProvider.overrideWithValue(resolver),
        ],
      );
}
