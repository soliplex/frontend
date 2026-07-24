import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/app_module.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.document_browser_url');

/// Derives a document's clickable browser URL from its internal document URI.
typedef DocumentBrowserUrlResolver = Uri? Function(String documentUri);

/// A deployment's rule for turning an internal document URI into a public
/// browser URL, used as a fallback for the citation source link.
///
/// The backend supplies a viewer `source_url` only for documents whose
/// ingestion attached it. When it is absent, the internal `documentUri`
/// (typically a `file://`/`s3://` path) is never itself launchable, so a
/// deployment can supply a rule that maps it to a public URL. The concrete
/// mapping lives in the consumer, injected through `standard(documentBrowserUrl:
/// ...)` / `standardFlavor(documentBrowserUrl: ...)`. The default resolves
/// nothing, so the standard build shows the raw document URI instead of a link.
///
/// Only the citation source link consults this; the document listing and filter
/// read `RagDocument.sourceUrl` directly.
final documentBrowserUrlResolverProvider =
    Provider<DocumentBrowserUrlResolver>((_) => (_) => null);

/// The launchable browser URL for a cited document: the viewer [sourceUrl] when
/// present, else a URL the [resolver] derives from [documentUri]. The resolver
/// result is validated as a web URL, so a resolver that returns a
/// non-launchable value yields null rather than a dead link.
Uri? resolveDocumentBrowserUrl(
  DocumentBrowserUrlResolver resolver, {
  required Uri? sourceUrl,
  required String documentUri,
}) {
  if (sourceUrl != null) return sourceUrl;

  final Uri? derived;
  try {
    derived = resolver(documentUri);
  } catch (error, stackTrace) {
    // The resolver is consumer-supplied; a throw must degrade to no link, not
    // crash the widget that renders it.
    _logger.error(
      'documentBrowserUrl resolver threw',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
  if (derived == null) return null;

  final url = launchableWebUrl(derived.toString());
  if (url == null) {
    _logger.warning(
      'documentBrowserUrl resolver returned a non-launchable URL '
      '(scheme: ${derived.scheme})',
    );
  }
  return url;
}

/// Installs [resolver] as the app-wide [documentBrowserUrlResolverProvider]
/// override. Added by `standardFlavor` when a `documentBrowserUrl` is supplied.
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
