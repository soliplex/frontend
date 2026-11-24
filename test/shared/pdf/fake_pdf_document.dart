import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_document_view.dart';

/// Stands in for pdfrx: records what the viewer asks of the document, and
/// lets a test set what the document reports.
class FakePdfDocument implements PdfDocumentController {
  final statusSignal = signal(const PdfViewStatus(pageNumber: 1, pageCount: 5));
  final calls = <String>[];
  final searches = <String>[];

  /// What [takeSelection] gives next.
  PdfSelectionResult? selection;

  @override
  ReadonlySignal<PdfViewStatus> get status => statusSignal;

  void report(PdfViewStatus status) => statusSignal.value = status;

  @override
  Future<void> goToPage(int pageNumber) async =>
      calls.add('goToPage $pageNumber');

  @override
  Future<void> zoomIn() async => calls.add('zoomIn');

  @override
  Future<void> zoomOut() async => calls.add('zoomOut');

  @override
  void search(String query) => searches.add(query);

  @override
  Future<void> nextMatch() async => calls.add('nextMatch');

  @override
  Future<void> previousMatch() async => calls.add('previousMatch');

  @override
  Future<PdfSelectionResult?> takeSelection() async {
    calls.add('takeSelection');
    final taken = selection;
    selection = null;
    return taken;
  }
}

/// A [PdfDocumentViewFactory] whose views do nothing on their own: a test
/// reads [requests] and drives them by calling [PdfDocumentViewRequest]'s
/// callbacks, or [ready] to open the last one.
class FakePdfDocumentViews {
  final requests = <PdfDocumentViewRequest>[];
  final document = FakePdfDocument();

  PdfDocumentViewRequest get last => requests.last;

  Widget call(PdfDocumentViewRequest request) {
    requests.add(request);
    return const SizedBox.expand(key: ValueKey('fake-pdf-document'));
  }

  /// Opens the last requested document with [document].
  void ready() => last.onReady(document);
}
