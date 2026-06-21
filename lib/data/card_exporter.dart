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
    double dpi = 300,
  }) async {
    final bytes = await exportCardPng(card, refs, dpi: dpi);
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
    double dpi = 300,
  }) async {
    final bytes = await exportCardPng(card, refs, dpi: dpi);
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
    double dpi = 300,
  }) async {
    final bytes = await exportCardPng(card, refs, dpi: dpi);
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
