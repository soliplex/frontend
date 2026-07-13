import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';

/// Page images for a chunk, with chunk text highlighted.
///
/// Used to display visual context for PDF citations.
@immutable
class ChunkVisualization {
  /// Creates a ChunkVisualization with the given properties.
  ChunkVisualization({
    required this.chunkId,
    required this.documentUri,
    required List<String> imagesBase64,
  }) : imagesBase64 = List.unmodifiable(imagesBase64);

  /// Creates a ChunkVisualization from JSON.
  factory ChunkVisualization.fromJson(Map<String, dynamic> json) {
    final chunkId = json['chunk_id'];
    if (chunkId is! String) {
      throw MalformedResponseException(
        message: 'ChunkVisualization: expected a String "chunk_id", '
            'got ${chunkId.runtimeType}.',
      );
    }
    final documentUri = json['document_uri'];
    if (documentUri != null && documentUri is! String) {
      throw MalformedResponseException(
        message: 'ChunkVisualization: expected a String or null '
            '"document_uri", got ${documentUri.runtimeType}.',
      );
    }
    final rawImages = json['images_base_64'];
    if (rawImages is! List) {
      throw MalformedResponseException(
        message: 'ChunkVisualization: expected a list "images_base_64", '
            'got ${rawImages.runtimeType}.',
      );
    }
    final images = <String>[];
    for (final entry in rawImages) {
      if (entry is! String) {
        throw MalformedResponseException(
          message: 'ChunkVisualization: expected String entries in '
              '"images_base_64", got ${entry.runtimeType}.',
        );
      }
      images.add(entry);
    }
    return ChunkVisualization(
      chunkId: chunkId,
      documentUri: documentUri as String?,
      imagesBase64: images,
    );
  }

  /// The chunk ID this visualization is for.
  final String chunkId;

  /// The document URI, if available.
  final String? documentUri;

  /// Base64-encoded page images with chunk text highlighted.
  final List<String> imagesBase64;

  /// Whether there are images to display.
  bool get hasImages => imagesBase64.isNotEmpty;

  /// Number of page images.
  int get imageCount => imagesBase64.length;

  /// Converts this ChunkVisualization to JSON.
  Map<String, dynamic> toJson() => {
        'chunk_id': chunkId,
        'document_uri': documentUri,
        'images_base_64': imagesBase64,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChunkVisualization &&
          chunkId == other.chunkId &&
          documentUri == other.documentUri &&
          const ListEquality<String>().equals(imagesBase64, other.imagesBase64);

  @override
  int get hashCode => Object.hash(
        chunkId,
        documentUri,
        const ListEquality<String>().hash(imagesBase64),
      );

  @override
  String toString() =>
      'ChunkVisualization(chunkId: $chunkId, images: $imageCount)';
}
