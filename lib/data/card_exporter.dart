// lib/data/card_exporter.dart
//
// Renders a card to PNG via the shared export path and saves it to a file the
// user chooses. Reused by the Card Editor now and Collection's per-card Export
// later. On desktop/web this is a Save-as dialog; a mobile gallery branch (gal)
// can be added when those platforms are targeted.

import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../model/card_model.dart';
import '../rendering/export.dart';

class CardExporter {
  /// Renders [card] to PNG and prompts a Save-as dialog. Returns the written
  /// path, or null if the user cancelled. Throws on a write error.
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
