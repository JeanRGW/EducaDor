import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Resizes a device image to a WebP cover within [maxDimension] px and
/// [maxBytes]. Returns null when the source cannot be decoded or never fits.
Uint8List? processCoverImage(
  Uint8List bytes, {
  int maxDimension = 1200,
  int maxBytes = 200 * 1024,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final largest = max(decoded.width, decoded.height);
  for (final target in [maxDimension, 1000, 800]) {
    if (target > maxDimension) continue;
    final candidate = largest <= target
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? target : null,
            height: decoded.height > decoded.width ? target : null,
          );
    for (final quality in [82, 72, 62, 52]) {
      final encoded = img.encodeWebP(
        candidate,
        lossless: false,
        quality: quality,
      );
      if (encoded.length <= maxBytes) return encoded;
    }
  }
  return null;
}
