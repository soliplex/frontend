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

  factory PassageBox._fromJson(
    Object? json,
    String field, {
    String model = 'DocumentBoxes',
  }) {
    if (json is! Map<String, dynamic>) {
      throw MalformedResponseException(
        message: '$model: expected objects in "$field", '
            'got ${json.runtimeType}.',
      );
    }
    final page = json['page'];
    if (page is! int) {
      throw MalformedResponseException(
        message: '$model: expected an int "page" in "$field", '
            'got ${page.runtimeType}.',
      );
    }
    double edge(String name) {
      final value = json[name];
      if (value is! num) {
        throw MalformedResponseException(
          message: '$model: expected a number "$name" in "$field", '
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
    final documentId = _documentIdOf(json, 'DocumentBoxes');
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

/// The `document_id` of a response in PDF points, after checking that its
/// `coord_origin` is BOTTOMLEFT, the only origin a viewer is given.
String _documentIdOf(Map<String, dynamic> json, String model) {
  final documentId = json['document_id'];
  if (documentId is! String) {
    throw MalformedResponseException(
      message: '$model: expected a String "document_id", '
          'got ${documentId.runtimeType}.',
    );
  }
  final origin = json['coord_origin'];
  if (origin != 'BOTTOMLEFT') {
    throw MalformedResponseException(
      message: '$model: expected "coord_origin" BOTTOMLEFT, '
          'got ${origin is String ? origin : origin.runtimeType}.',
    );
  }
  return documentId;
}

/// One block of a document's text, where it sits on its page.
///
/// A block is one layout item from the backend's model — a paragraph, a
/// heading, a table — so its [box] is the item's, not a line's or a word's.
@immutable
class DocumentTextBlock {
  /// Creates a block of [text] in [box].
  const DocumentTextBlock({
    required this.box,
    required this.text,
    required this.label,
  });

  factory DocumentTextBlock._fromJson(Object? json) {
    final box = PassageBox._fromJson(json, 'blocks', model: 'DocumentText');
    // PassageBox has checked that it is an object.
    final fields = json! as Map<String, dynamic>;
    String field(String name) {
      final value = fields[name];
      if (value is! String) {
        throw MalformedResponseException(
          message: 'DocumentText: expected a String "$name" in "blocks", '
              'got ${value.runtimeType}.',
        );
      }
      return value;
    }

    return DocumentTextBlock(
      box: box,
      text: field('text'),
      label: field('label'),
    );
  }

  /// Where the block is.
  final PassageBox box;

  /// The block's text; a table's is Markdown.
  final String text;

  /// The backend's label for the item: `text`, `section_header`, `table`…
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentTextBlock &&
          other.box == box &&
          other.text == text &&
          other.label == label;

  @override
  int get hashCode => Object.hash(box, text, label);

  @override
  String toString() => 'DocumentTextBlock($box, $label, ${text.length} chars)';
}

/// A document's text as the backend read it, block by block, in reading
/// order.
///
/// For a scanned PDF this is the text OCR recovered when it was ingested,
/// which the PDF itself does not carry.
@immutable
class DocumentText {
  /// Creates the text of [documentId].
  DocumentText({
    required this.documentId,
    required List<DocumentTextBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  /// Creates DocumentText from JSON.
  ///
  /// Throws [MalformedResponseException] when a field is missing or of the
  /// wrong type, or when `coord_origin` is not `BOTTOMLEFT`.
  factory DocumentText.fromJson(Map<String, dynamic> json) {
    final documentId = _documentIdOf(json, 'DocumentText');
    final raw = json['blocks'];
    if (raw is! List) {
      throw MalformedResponseException(
        message: 'DocumentText: expected a list "blocks", '
            'got ${raw.runtimeType}.',
      );
    }
    return DocumentText(
      documentId: documentId,
      blocks: [for (final block in raw) DocumentTextBlock._fromJson(block)],
    );
  }

  /// The document the text is from.
  final String documentId;

  /// The blocks, in reading order.
  final List<DocumentTextBlock> blocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentText &&
          other.documentId == documentId &&
          const ListEquality<DocumentTextBlock>().equals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(
        documentId,
        const ListEquality<DocumentTextBlock>().hash(blocks),
      );

  @override
  String toString() => 'DocumentText($documentId, ${blocks.length} blocks)';
}
