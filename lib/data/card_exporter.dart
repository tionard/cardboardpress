// lib/data/card_exporter.dart
//
// Renders a card to PNG via the shared export path, then hands the bytes off in
// a platform-appropriate way:
//   * Desktop (Windows) — a Save-as dialog (file_picker); the user picks where.
//   * Android — save into the photo gallery (gal), or push it to the system
//     share sheet (share_plus).
//
// The rendering itself (exportCardPng) is identical everywhere; only the final
// "where do the bytes go" tail differs, so the exported image is byte-identical
// across platforms — and identical to the on-screen preview, since both run the
// same paintCard.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../model/card_model.dart';
import '../rendering/export.dart';

/// Thrown by [CardExporter.saveToGallery] when the user denies photo access.
class GalleryAccessDenied implements Exception {
  const GalleryAccessDenied();
  @override
  String toString() => 'Gallery access was denied';
}

class CardExporter {
  /// Desktop Save-as. Renders [card] to PNG and prompts for a location.
  /// Returns the written path, or null if the user cancelled. Throws on a
  /// write error.
  Future<String?> exportToFile(
    CardData card,
    CardRefs refs, {
    String? setAbbr,
    double dpi = kProExportDpi,
    bool proUnlocked = false,
  }) async {
    final q = resolveExportQuality(requestedDpi: dpi, proUnlocked: proUnlocked);
    final bytes =
        await exportCardPng(card, refs, dpi: q.dpi, watermark: q.watermark);
    final suggested = exportFileName(_safe(_cardName(card)), setAbbr: setAbbr);

    final path = await FilePicker.saveFile(
      dialogTitle: 'Export card as PNG',
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: ['png'],
      bytes: bytes, // used on mobile/web; desktop returns a path to write
    );
    if (path == null) return null;

    // On desktop saveFile returns the chosen path without writing — write here.
    final out = path.toLowerCase().endsWith('.png') ? path : '$path.png';
    await File(out).writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Android: render [card] and save the PNG into the device photo gallery.
  /// Returns the file name used. Throws [GalleryAccessDenied] if the user
  /// refuses access (and may throw a GalException on other failures).
  Future<String> saveToGallery(
    CardData card,
    CardRefs refs, {
    String? setAbbr,
    double dpi = kProExportDpi,
    bool proUnlocked = false,
  }) async {
    final q = resolveExportQuality(requestedDpi: dpi, proUnlocked: proUnlocked);
    final bytes =
        await exportCardPng(card, refs, dpi: q.dpi, watermark: q.watermark);
    final fileName = exportFileName(_safe(_cardName(card)), setAbbr: setAbbr);

    final granted = await Gal.requestAccess();
    if (!granted) throw const GalleryAccessDenied();

    // gal derives the file extension from the PNG byte header, so hand it the
    // bare name (no .png) to avoid a doubled extension.
    final bareName = fileName.replaceAll(RegExp(r'\.png$'), '');
    await Gal.putImageBytes(bytes, name: bareName);
    return fileName;
  }

  /// Render [card] and open the system share sheet with the PNG attached.
  /// Returns true if the user completed a share, false if they dismissed it.
  Future<bool> shareImage(
    CardData card,
    CardRefs refs, {
    String? setAbbr,
    double dpi = kProExportDpi,
    bool proUnlocked = false,
  }) async {
    final q = resolveExportQuality(requestedDpi: dpi, proUnlocked: proUnlocked);
    final bytes =
        await exportCardPng(card, refs, dpi: q.dpi, watermark: q.watermark);
    final fileName = exportFileName(_safe(_cardName(card)), setAbbr: setAbbr);

    // The share sheet needs a real file on disk; the OS cleans up the temp dir.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
    return result.status == ShareResultStatus.success;
  }

  // ---- pre-rendered document delivery (sheets, PDFs, JSON) ----
  // These take BYTES, not cards — the sheet/JSON composers render upstream;
  // this half only lands files, mirroring the single-card split above.

  /// Android: save several pre-rendered PNGs into the photo gallery. Returns
  /// how many were saved; throws [GalleryAccessDenied] on refusal.
  Future<int> saveImagesToGallery(List<(String, Uint8List)> images) async {
    final granted = await Gal.requestAccess();
    if (!granted) throw const GalleryAccessDenied();
    var saved = 0;
    for (final (name, bytes) in images) {
      final bare = _safe(name).replaceAll(RegExp(r'\.png$'), '');
      await Gal.putImageBytes(bytes, name: bare);
      saved++;
    }
    return saved;
  }

  /// Desktop: pick a folder once and write every image into it. Returns the
  /// chosen directory, or null if the user cancelled.
  Future<String?> saveImagesToDirectory(
    List<(String, Uint8List)> images, {
    String dialogTitle = 'Choose a folder for the exported sheets',
  }) async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (dir == null) return null;
    for (final (name, bytes) in images) {
      await File('$dir${Platform.pathSeparator}${_safe(name)}')
          .writeAsBytes(bytes, flush: true);
    }
    return dir;
  }

  /// Save a single non-image document (PDF, JSON) via a Save-as dialog on
  /// desktop or the system file saver on mobile. Returns the written path
  /// (desktop) / the picker's result (mobile), or null when cancelled.
  Future<String?> saveDocument(
    Uint8List bytes, {
    required String fileName,
    required String extension,
    String dialogTitle = 'Save file',
  }) async {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: _safe(fileName),
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes, // used on mobile; desktop returns a path to write
    );
    if (path == null) return null;
    final out =
        path.toLowerCase().endsWith('.$extension') ? path : '$path.$extension';
    // On mobile the picker already wrote the bytes; writing again is a no-op
    // overwrite. On desktop this IS the write.
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(out).writeAsBytes(bytes, flush: true);
    }
    return out;
  }

  // The card's name comes from its Name field's content.
  String _cardName(CardData card) {
    for (final f in card.fields) {
      if (f.type == FieldType.name) return card.textContent[f.id] ?? '';
    }
    return '';
  }

  // Strip characters that are invalid in Windows filenames.
  String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
}
