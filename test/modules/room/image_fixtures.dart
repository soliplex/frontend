import 'dart:convert';
import 'dart:typed_data';

/// A real 1×1 image in each type a message may carry.
///
/// Decodable on purpose. A composer thumbnail renders these, so bytes that would
/// not decode leave a test swallowing a decode failure — and, more to the point,
/// a transform written the way transforms get written, falling back to the
/// original on a decode failure, would pass over undecodable bytes untouched and
/// leave the passthrough assertions green while re-encoding every real photo.
///
/// `attachable_images_test.dart` is what holds them to it, in 'every fixture is
/// an image an encoder could act on'. That test and this paragraph go together:
/// neither is worth keeping without the other.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB'
  '5Sfe/AAAAABJRU5ErkJggg==',
);

final onePixelGif = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);

final onePixelWebp = base64Decode(
  'UklGRhwAAABXRUJQVlA4TA8AAAAvAAAAAAcQ/Y/+ByKi/wEA',
);

final onePixelJpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoM'
  'DAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsN'
  'FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAAR'
  'CAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAA'
  'AgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK'
  'FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
  'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl'
  '5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
  'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYk'
  'NOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE'
  'hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk'
  '5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD50ooor8MP9Uz/2Q==',
);

/// The header an iPhone's HEIC opens with: a `ftyp` box declaring the `heic`
/// brand.
///
/// Only a header, where the others are whole images, because that is all a type
/// sniffer reads and no allow-list carries HEIC — nothing decodes these bytes.
final heicHeader = Uint8List.fromList([
  0x00, 0x00, 0x00, 0x18, // ftyp box length
  0x66, 0x74, 0x79, 0x70, // 'ftyp'
  0x68, 0x65, 0x69, 0x63, // 'heic' brand
  0x00, 0x00, 0x00, 0x00,
]);

/// Every type the allow-list carries, paired with real bytes of that type.
final Map<String, Uint8List> onePixelImages = {
  'image/png': onePixelPng,
  'image/jpeg': onePixelJpeg,
  'image/webp': onePixelWebp,
  'image/gif': onePixelGif,
};
