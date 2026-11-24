import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_document_view.dart';

void main() {
  group('PdfViewStatus', () {
    const status = PdfViewStatus(
      pageNumber: 2,
      pageCount: 9,
      hasSelection: true,
      searching: true,
      matchCount: 4,
      currentMatch: 1,
    );

    test('copyWith changes only what it is given', () {
      expect(status.copyWith(), status);
      expect(status.copyWith(pageNumber: 3).pageNumber, 3);
      expect(status.copyWith(pageCount: 10).pageCount, 10);
      expect(status.copyWith(hasSelection: false).hasSelection, isFalse);
      expect(status.copyWith(searching: false).searching, isFalse);
      expect(status.copyWith(matchCount: 0).matchCount, 0);
      expect(status.copyWith(pageNumber: 3).matchCount, 4);
    });

    test('copyWith can clear the current match', () {
      expect(status.copyWith(currentMatch: () => null).currentMatch, isNull);
      expect(status.copyWith(currentMatch: () => 3).currentMatch, 3);
    });

    test('is equal by value', () {
      const same = PdfViewStatus(
        pageNumber: 2,
        pageCount: 9,
        hasSelection: true,
        searching: true,
        matchCount: 4,
        currentMatch: 1,
      );
      expect(status, same);
      expect(status.hashCode, same.hashCode);
      expect(status, isNot(status.copyWith(matchCount: 5)));
    });
  });

  test('a request opens from bytes or from a URI, not both', () {
    PdfDocumentViewRequest request({Uint8List? bytes, Uri? uri}) =>
        PdfDocumentViewRequest(
          bytes: bytes,
          uri: uri,
          sourceName: 'x',
          onReady: (_) {},
          onLoadFailed: (_, __) {},
          passwordProvider: () => null,
        );

    expect(() => request(bytes: Uint8List(1)), returnsNormally);
    expect(
        () => request(uri: Uri.parse('https://e.com/a.pdf')), returnsNormally);
    expect(() => request(), throwsAssertionError);
    expect(
      () => request(bytes: Uint8List(1), uri: Uri.parse('https://e.com/a.pdf')),
      throwsAssertionError,
    );
  });
}
