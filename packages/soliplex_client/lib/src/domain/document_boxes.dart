import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';

/// One layout item's box on a page of a PDF: PDF points, with the origin at
/// the page's bottom left, as the PDF's own coordinates are.
///
/// An item is one cluster from the backend's layout model — a paragraph or a
/// larger block — so a box is never finer than that.
@immutable
class PassageBox {
  /// Creates a box on [page], 1-based.
  const PassageBox({
    required this.page,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory PassageBox._fromJson(Object? json, String field) {
    if (json is! Map<String, dynamic>) {
      throw MalformedResponseException(
        message: 'DocumentBoxes: expected objects in "$field", '
            'got ${json.runtimeType}.',
      );
    }
    final page = json['page'];
    if (page is! int) {
      throw MalformedResponseException(
        message: 'DocumentBoxes: expected an int "page" in "$field", '
            'got ${page.runtimeType}.',
      );
    }
    double edge(String name) {
      final value = json[name];
      if (value is! num) {
        throw MalformedResponseException(
          message: 'DocumentBoxes: expected a number "$name" in "$field", '
              'got ${value.runtimeType}.',
        );
      }
      return value.toDouble();
    }

    return PassageBox(
      page: page,
      left: edge('left'),
      top: edge('top'),
      right: edge('right'),
      bottom: edge('bottom'),
    );
  }

  /// The 1-based page the box is on.
  final int page;

  /// The left edge, in PDF points from the page's left.
  final double left;

  /// The top edge, in PDF points from the page's bottom.
  final double top;

  /// The right edge, in PDF points from the page's left.
  final double right;

  /// The bottom edge, in PDF points from the page's bottom.
  final double bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PassageBox &&
          other.page == page &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom;

  @override
  int get hashCode => Object.hash(page, left, top, right, bottom);

  @override
  String toString() => 'PassageBox(p.$page, $left, $top, $right, $bottom)';
}

/// Where a citation's passage sits in its document's pages.
///
/// [anchor] boxes are the cited chunks' own items; [context] boxes are the rest
/// of the context the model read, which a viewer draws more faintly.
@immutable
class DocumentBoxes {
  /// Creates the boxes of a passage in [documentId].
  DocumentBoxes({
    required this.documentId,
    required List<PassageBox> anchor,
    required List<PassageBox> context,
  })  : anchor = List.unmodifiable(anchor),
        context = List.unmodifiable(context);

  /// Creates DocumentBoxes from JSON.
  ///
  /// Throws [MalformedResponseException] when a field is missing or of the
  /// wrong type, or when `coord_origin` is not `BOTTOMLEFT`.
  factory DocumentBoxes.fromJson(Map<String, dynamic> json) {
    final documentId = json['document_id'];
    if (documentId is! String) {
      throw MalformedResponseException(
        message: 'DocumentBoxes: expected a String "document_id", '
            'got ${documentId.runtimeType}.',
      );
    }
    final origin = json['coord_origin'];
    if (origin != 'BOTTOMLEFT') {
      throw MalformedResponseException(
        message: 'DocumentBoxes: expected "coord_origin" BOTTOMLEFT, '
            'got ${origin is String ? origin : origin.runtimeType}.',
      );
    }
    List<PassageBox> boxes(String field) {
      final raw = json[field];
      if (raw is! List) {
        throw MalformedResponseException(
          message: 'DocumentBoxes: expected a list "$field", '
              'got ${raw.runtimeType}.',
        );
      }
      return [for (final box in raw) PassageBox._fromJson(box, field)];
    }

    return DocumentBoxes(
      documentId: documentId,
      anchor: boxes('anchor'),
      context: boxes('context'),
    );
  }

  /// The document the boxes are in.
  final String documentId;

  /// The boxes of the cited chunks' own items.
  final List<PassageBox> anchor;

  /// The boxes of the rest of the context the model read.
  final List<PassageBox> context;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    const boxes = ListEquality<PassageBox>();
    return other is DocumentBoxes &&
        other.documentId == documentId &&
        boxes.equals(other.anchor, anchor) &&
        boxes.equals(other.context, context);
  }

  @override
  int get hashCode => Object.hash(
        documentId,
        const ListEquality<PassageBox>().hash(anchor),
        const ListEquality<PassageBox>().hash(context),
      );

  @override
  String toString() => 'DocumentBoxes($documentId, '
      '${anchor.length} anchor, ${context.length} context)';
}
