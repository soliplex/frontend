import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Derives a document's clickable browser URL from its `documentUri`.
typedef DocumentBrowserUrlResolver = Uri? Function(String documentUri);

/// TEMPORARY citation stopgap. Citations do not yet carry the backend
/// `source_url` metadata key (search hits omit document metadata), so a
/// deployment derives the browser link from the citation's `documentUri` by
/// injecting a resolver. The default resolves nothing, so the standard build
/// shows no citation link. Document listing and the document filter do NOT use
/// this — they read `RagDocument.sourceUrl` directly.
///
/// A fork injects its rule through a small [AppModule] and
/// `standardFlavor(extraModules: ...)`; the concrete URL rule lives in the
/// fork, never here:
///
/// ```dart
/// class DocumentLinkModule extends AppModule {
///   @override
///   String get namespace => 'document_link';
///
///   @override
///   ModuleRoutes build() => ModuleRoutes(
///         overrides: [
///           documentBrowserUrlResolverProvider.overrideWithValue(_resolve),
///         ],
///       );
///
///   // Deployment-specific: map an internal `file://…` path to a public
///   // browser URL, or return null to render no link.
///   static Uri? _resolve(String documentUri) => null;
/// }
/// // standardFlavor(extraModules: (kit) => [DocumentLinkModule()])
/// ```
///
/// DELETE this provider, its `citations_section.dart` call site, and any fork
/// module overriding it once the backend surfaces `source_url` on citations;
/// the citation line then reads the field like the document surfaces do.
final documentBrowserUrlResolverProvider =
    Provider<DocumentBrowserUrlResolver>((_) => (_) => null);
