import 'package:blurhash_dart/blurhash_dart.dart' as bh;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Result of a profile-image processing pipeline run.
@immutable
class ProcessedImageResult {
  const ProcessedImageResult({
    required this.bytes,
    required this.contentType,
    required this.fileExtension,
    required this.blurhash,
  });

  /// Compressed image bytes ready for upload to Supabase storage.
  final Uint8List bytes;

  /// HTTP `Content-Type` to pass to `FileOptions(contentType: ...)`.
  final String contentType;

  /// File extension WITHOUT the leading dot (e.g. `webp`).
  final String fileExtension;

  /// BlurHash string suitable for `BlurHash.decode()` placeholders.
  final String blurhash;
}

/// Pure utility namespace — no instance state, safe to call from any isolate
/// boundary (BlurHash encoding can be slow, so we run it via [compute]).
abstract final class ImageProcessingService {
  /// Compresses [original] to WebP at [quality] (0-100), bounded to a
  /// max edge of [maxEdge], and produces a BlurHash from a downscaled copy
  /// of the same source.
  ///
  /// Falls back to JPEG when WebP compression is unavailable on the host
  /// platform (rare; mainly older Android x86 emulators).
  static Future<ProcessedImageResult> compressAndHash({
    required Uint8List original,
    int quality = 75,
    int maxEdge = 1024,
  }) async {
    Uint8List compressed;
    String contentType = 'image/webp';
    String fileExtension = 'webp';
    try {
      compressed = await FlutterImageCompress.compressWithList(
        original,
        quality: quality,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.webp,
      );
      if (compressed.isEmpty) {
        throw StateError('empty webp output');
      }
    } catch (_) {
      compressed = await FlutterImageCompress.compressWithList(
        original,
        quality: quality,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );
      contentType = 'image/jpeg';
      fileExtension = 'jpg';
    }

    final String blurhash = await compute(
      _encodeBlurhash,
      _BlurhashJob(bytes: original, maxEdge: maxEdge),
    );

    return ProcessedImageResult(
      bytes: compressed,
      contentType: contentType,
      fileExtension: fileExtension,
      blurhash: blurhash,
    );
  }
}

class _BlurhashJob {
  const _BlurhashJob({required this.bytes, required this.maxEdge});
  final Uint8List bytes;
  final int maxEdge;
}

String _encodeBlurhash(_BlurhashJob job) {
  try {
    final img.Image? decoded = img.decodeImage(job.bytes);
    if (decoded == null) return '';
    // Downscale: BlurHash quality is unaffected past ~32px and tiny inputs
    // make encoding ~50× faster.
    final int targetEdge = job.maxEdge.clamp(16, 64);
    final int width = decoded.width >= decoded.height
        ? targetEdge
        : (decoded.width * targetEdge / decoded.height).round();
    final int height = decoded.height >= decoded.width
        ? targetEdge
        : (decoded.height * targetEdge / decoded.width).round();
    final img.Image small = img.copyResize(
      decoded,
      width: width.clamp(1, targetEdge),
      height: height.clamp(1, targetEdge),
      interpolation: img.Interpolation.linear,
    );
    final bh.BlurHash hash = bh.BlurHash.encode(
      small,
      numCompX: 4,
      numCompY: 3,
    );
    return hash.hash;
  } catch (_) {
    return '';
  }
}
