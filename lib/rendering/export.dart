// lib/rendering/export.dart
//
// The export path. Notice it does NOT contain any card-drawing logic of its
// own — it just runs `paintCard` (the same one the preview uses) onto a bigger
// canvas and reads back the pixels as PNG. Same code, bigger surface => the
// export is faithful to the preview by construction (spec §6).

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/card_model.dart';
import 'paint_card.dart';

/// Renders [card] at [dpi] and returns PNG bytes.
///
/// A standard poker card is 2.5×3.5 in. Pixels = inches × dpi:
///   300 dpi → 750×1050,  600 dpi → 1500×2100.
Future<Uint8List> exportCardPng(
  CardData card,
  CardRefs refs, {
  double dpi = 300,
}) async {
  final px = ui.Size(card.widthInches * dpi, card.heightInches * dpi);

  // A PictureRecorder is an off-screen canvas that records draw calls.
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Offset.zero & px);

  paintCard(canvas, px, card, refs); // <-- the SAME function as the preview

  final picture = recorder.endRecording();
  final image = await picture.toImage(px.width.round(), px.height.round());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  picture.dispose();
  image.dispose();

  return byteData!.buffer.asUint8List();
}

/// Builds the export file name (spec §6): `[setAbbr]_[cardName]_[ddMMyyyy].png`.
/// The `setAbbr_` segment is dropped for cards with no set.
String exportFileName(String cardName, {String? setAbbr, DateTime? now}) {
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(d.day)}${two(d.month)}${d.year}';
  final safeName = cardName.trim().isEmpty ? 'card' : cardName.trim();
  final prefix = (setAbbr == null || setAbbr.isEmpty) ? '' : '${setAbbr}_';
  return '$prefix${safeName}_$date.png';
}
