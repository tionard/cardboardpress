// lib/data/image_import.dart
//
// Upload validation + downscaling for user-picked images — the gate every
// upload path runs through before ImageStore.save. Policy (per kind):
//
//   kind        max side   min side   max file
//   artwork     2048 px    1 px       10 MB
//   frame       1024 px    32 px       4 MB
//   symbol      1024 px    32 px       4 MB
//   textSymbol   512 px    1 px        2 MB
//
// Behaviour: an oversized FILE, an unreadable file, or a too-small image is
// REJECTED (ImageImportException with a user-readable message); oversized
// DIMENSIONS are silently downscaled to the cap (aspect preserved, re-encoded
// as PNG) with a notice the caller can show. The order matters for safety:
// the byte-size check runs BEFORE any decode (a decode-bomb guard), and
// dimensions are read via ImageDescriptor — cheap header parsing — so a
// 100-megapixel image never gets fully decoded at its original size.
//
// Deliberate property: an image already within limits passes through
// BYTE-IDENTICAL (the exact input buffer, no re-encode), so the content-hash
// dedup in ImageStore keeps recognising repeat uploads of the same file.
// Explicit-id saves (seeded defaults, backup restore) do not run through
// here — they were validated when first imported.

import 'dart:typed_data';
import 'dart:ui' as ui;

/// What the image is being uploaded AS — picks the limit set above.
enum ImageImportKind { artwork, frame, symbol, textSymbol }

/// A rejected upload, with a message ready to show the user.
class ImageImportException implements Exception {
  final String message;
  const ImageImportException(this.message);
  @override
  String toString() => message;
}

/// A validated (and possibly downscaled) upload, ready for ImageStore.save.
class ImportedImage {
  final Uint8List bytes;
  final String ext;
  final int width;
  final int height;

  /// The original dimensions when the image was downscaled; null when the
  /// input passed through untouched.
  final ({int width, int height})? downscaledFrom;

  const ImportedImage({
    required this.bytes,
    required this.ext,
    required this.width,
    required this.height,
    this.downscaledFrom,
  });

  /// A user-facing note about what happened, or null if nothing did.
  String? get notice {
    final from = downscaledFrom;
    if (from == null) return null;
    return 'Image scaled down from ${from.width}×${from.height} '
        'to $width×$height.';
  }
}

class _Limits {
  final int maxSide;
  final int minSide;
  final int maxBytes;
  const _Limits(
      {required this.maxSide, required this.minSide, required this.maxBytes});
}

const _mb = 1024 * 1024;

_Limits _limitsFor(ImageImportKind kind) => switch (kind) {
      ImageImportKind.artwork =>
        const _Limits(maxSide: 2048, minSide: 1, maxBytes: 10 * _mb),
      ImageImportKind.frame ||
      ImageImportKind.symbol =>
        const _Limits(maxSide: 1024, minSide: 32, maxBytes: 4 * _mb),
      ImageImportKind.textSymbol =>
        const _Limits(maxSide: 512, minSide: 1, maxBytes: 2 * _mb),
    };

/// Validate [bytes] as an upload of [kind]; returns the bytes to store —
/// the input itself when within limits, a PNG re-encode when downscaled.
/// Throws [ImageImportException] with a showable message on rejection.
Future<ImportedImage> processImportedImage(
  Uint8List bytes, {
  required ImageImportKind kind,
  String ext = 'png',
}) async {
  final lim = _limitsFor(kind);

  if (bytes.isEmpty) {
    throw const ImageImportException('That file is empty.');
  }
  // Byte-size guard BEFORE any decode work.
  if (bytes.length > lim.maxBytes) {
    final mb = (bytes.length / _mb).toStringAsFixed(1);
    throw ImageImportException(
        'That file is too large ($mb MB — the limit here is '
        '${lim.maxBytes ~/ _mb} MB).');
  }

  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? desc;
  try {
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      desc = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      throw const ImageImportException(
          "That file couldn't be read as an image.");
    }

    final w = desc.width;
    final h = desc.height;
    if (w < lim.minSide || h < lim.minSide) {
      throw ImageImportException('That image is too small ($w×$h — at least '
          '${lim.minSide}×${lim.minSide} is needed here).');
    }

    if (w <= lim.maxSide && h <= lim.maxSide) {
      // Within limits: pass the exact input through (dedup-stable).
      return ImportedImage(
          bytes: bytes, ext: ext.toLowerCase(), width: w, height: h);
    }

    // Downscale so the longest side hits the cap, aspect preserved. The
    // descriptor decodes straight to the target size — the full-resolution
    // bitmap never exists in memory.
    final scale = lim.maxSide / (w > h ? w : h);
    final tw = (w * scale).round().clamp(1, lim.maxSide);
    final th = (h * scale).round().clamp(1, lim.maxSide);
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) {
      throw const ImageImportException("That image couldn't be processed.");
    }
    return ImportedImage(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ext: 'png',
      width: tw,
      height: th,
      downscaledFrom: (width: w, height: h),
    );
  } finally {
    desc?.dispose();
    buffer?.dispose();
  }
}
