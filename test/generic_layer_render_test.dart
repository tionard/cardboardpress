// test/generic_layer_render_test.dart
//
// LAYER REDESIGN — Phase 4 (Drop B) gate for the generic render path.
//
// `_paintGenericLayer` draws a generic layer's aspects in the fixed sub-order
// fill -> image -> border -> outline -> foil -> text. Field-derived layers never
// reach it (they carry neither an image nor a foil aspect), so the existing
// parity tests already prove migrated cards are unchanged. This test exercises
// the genuinely-new capabilities directly, with synthetic layers, so the drawer
// is proven before the authoring UI (Drop C) relies on it:
//
//   * a fixed image drawn as-is inside its rect,
//   * a fixed image with a tint drawn as a coloured silhouette,
//   * a per-layer foil visibly altering what's beneath it.
//
// Run: `flutter test`.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:cardboardpress/rendering/paint_card.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solidImage(int argb, {int w = 8, int h = 8}) {
  final c = Completer<ui.Image>();
  final px = Uint8List(w * h * 4);
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = r;
    px[i * 4 + 1] = g;
    px[i * 4 + 2] = b;
    px[i * 4 + 3] = a;
  }
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<Uint8List> _render(CardData card, CardRefs refs, ui.Size size) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  paintCard(canvas, size, card, refs);
  final pic = rec.endRecording();
  final img = await pic.toImage(size.width.round(), size.height.round());
  try {
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return d!.buffer.asUint8List();
  } finally {
    img.dispose();
    pic.dispose();
  }
}

(int, int, int, int) _px(Uint8List b, int x, int y, int w) {
  final i = (y * w + x) * 4;
  return (b[i], b[i + 1], b[i + 2], b[i + 3]);
}

int _firstDiff(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : n;
}

const _white = ColorRef.literal(ColorValue.single(ui.Color(0xFFFFFFFF)));
const _grey = ColorRef.literal(ColorValue.single(ui.Color(0xFF808080)));
const _blue = ColorRef.literal(ColorValue.single(ui.Color(0xFF0000FF)));

const _full = ui.Rect.fromLTRB(0, 0, 1, 1);
const _mid = ui.Rect.fromLTRB(0.3, 0.3, 0.7, 0.7);

// A plain full-card fill layer used as the backdrop. It has neither an image nor
// a foil aspect, so it renders through the unchanged _paintField path.
Layer _baseFill(ColorRef c) =>
    Layer(id: 'base', name: 'Base', frac: _full, fill: FillAspect(color: c));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = ui.Size(200, 280);
  const w = 200;

  test('generic fixed image draws as-is inside its rect', () async {
    final red = await _solidImage(0xFFFF0000);
    final card = CardData(
      baseColor: _white,
      fields: const [],
      layers: [
        _baseFill(_white),
        Layer(
          id: 'pic',
          name: 'Pic',
          frac: _mid,
          image: const ImageAspect(source: ImageSource.fixed, imageId: 'r'),
        ),
      ],
    );
    final px = await _render(card, CardRefs(images: {'r': red}), size);

    final (cr, cg, cb, _) = _px(px, 100, 140, w); // centre of the image rect
    expect(cr, greaterThan(200), reason: 'centre should be red');
    expect(cg, lessThan(60));
    expect(cb, lessThan(60));

    final (or, og, ob, _) = _px(px, 20, 140, w); // left of the image, on base
    expect(or, greaterThan(200), reason: 'outside the image stays white base');
    expect(og, greaterThan(200));
    expect(ob, greaterThan(200));
  });

  test('generic fixed image with a tint draws as a coloured silhouette',
      () async {
    // A fully-opaque source => a full silhouette filled with the tint colour.
    final mask = await _solidImage(0xFFFFFFFF);
    final card = CardData(
      baseColor: _white,
      fields: const [],
      layers: [
        _baseFill(_white),
        Layer(
          id: 'sil',
          name: 'Silhouette',
          frac: _mid,
          image: const ImageAspect(
              source: ImageSource.fixed, imageId: 'm', tint: _blue),
        ),
      ],
    );
    final px = await _render(card, CardRefs(images: {'m': mask}), size);

    final (cr, cg, cb, _) = _px(px, 100, 140, w);
    expect(cb, greaterThan(200), reason: 'silhouette filled with the blue tint');
    expect(cr, lessThan(60));
    expect(cg, lessThan(60));
  });

  test('generic foil layer visibly changes the pixels beneath it', () async {
    CardData grey({bool foil = false}) => CardData(
          baseColor: _grey,
          fields: const [],
          layers: [
            _baseFill(_grey),
            if (foil)
              const Layer(
                  id: 'foil', name: 'Foil', frac: _full, foil: FoilType.holo),
          ],
        );

    final plain = await _render(grey(), const CardRefs(), size);
    final foiled = await _render(grey(foil: true), const CardRefs(), size);

    expect(_firstDiff(plain, foiled), isNot(-1),
        reason: 'the foil overlay must alter the render');
  });
}
