// test/layer_render_parity_test.dart
//
// LAYER REDESIGN — Phase 1b verification gate.
//
// Proves the migration is faithful: for a template, rendering the card through
// the new layer-driven path (paintCardFromLayers ∘ templateToLayers) must be
// PIXEL-IDENTICAL to the current paintCard. Run: `flutter test`.
//
// Notes:
//  * An empty CardRefs is used on purpose. Colour refs resolve to their baked
//    snapshots (identical on both paths), and image draws (art / background /
//    watermark / set symbol) are skipped identically when unresolved — so the
//    test still exercises base, tint, fills, outlines, 9-slice geometry, text,
//    the art placeholder, footer zones, foil, and the border. (Decoded-image
//    parity is a golden-image concern for a later pass.)

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layer_migration.dart';
import 'package:cardboardpress/model/sample_card.dart';
import 'package:cardboardpress/rendering/paint_card.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _renderRgba(
    void Function(ui.Canvas, ui.Size) paint, ui.Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _firstDiff(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = ui.Size(375, 525); // 2.5" x 3.5" @ 150 dpi
  const refs = CardRefs();

  Future<void> expectParity(TemplateData template, CardData card) async {
    final layers = templateToLayers(template);
    final oldPixels =
        await _renderRgba((c, s) => paintCard(c, s, card, refs), size);
    final newPixels = await _renderRgba(
        (c, s) => paintCardFromLayers(c, s, card, layers, refs), size);

    expect(newPixels.length, equals(oldPixels.length),
        reason: 'rendered dimensions differ');
    final diff = _firstDiff(oldPixels, newPixels);
    expect(diff, equals(-1),
        reason: 'layer render diverges from paintCard at byte $diff '
            '(of ${oldPixels.length})');
  }

  group('layer render parity', () {
    for (final border in [true, false]) {
      for (final foil in [FoilType.none, FoilType.holo]) {
        test('border=$border foil=$foil', () async {
          final template = sampleTemplate(border: border);
          final card = composeCard(
            template,
            content: sampleContent(),
            foil: foil,
            footerPlaceholder: 'x', // fills footer zones so they render
          );
          await expectParity(template, card);
        });
      }
    }
  });
}
