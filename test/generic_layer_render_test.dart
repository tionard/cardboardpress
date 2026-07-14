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

/// Builds a test sprite where each pixel's colour comes from [argbAt] — used
/// to author 9-slice sprites with recognisable corner/edge/center regions.
Future<ui.Image> _pxImage(int w, int h, int Function(int x, int y) argbAt) {
  final c = Completer<ui.Image>();
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = argbAt(x, y);
      final i = (y * w + x) * 4;
      px[i] = (v >> 16) & 0xFF;
      px[i + 1] = (v >> 8) & 0xFF;
      px[i + 2] = v & 0xFF;
      px[i + 3] = (v >> 24) & 0xFF;
    }
  }
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
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
// a foil aspect (renders through the generic layer path).
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

  test('outline with an explicit colour renders without a fill', () async {
    const red = ColorRef.literal(ColorValue.single(ui.Color(0xFFFF0000)));
    CardData card({bool outline = false}) => CardData(
          baseColor: _white,
          fields: const [],
          layers: [
            _baseFill(_white),
            Layer(
              id: 'ol',
              name: 'Outlined',
              frac: _mid,
              outline:
                  outline ? const OutlineSpec(color: red, thickness: 0.02) : null,
            ),
          ],
        );

    final without = await _render(card(), const CardRefs(), size);
    final withOutline = await _render(card(outline: true), const CardRefs(), size);

    expect(_firstDiff(without, withOutline), isNot(-1),
        reason: 'a coloured outline must render even with no fill present');
  });

  test('per-card fill override repaints the layer', () async {
    const red = ColorRef.literal(ColorValue.single(ui.Color(0xFFFF0000)));
    CardData card({bool override = false}) => CardData(
          baseColor: _white,
          fields: const [],
          layers: [
            _baseFill(_white),
            Layer(id: 'box', name: 'Box', frac: _mid, fill: FillAspect(color: _grey)),
          ],
          fillColors: override ? const {'box': red} : const {},
        );

    final base = await _render(card(), const CardRefs(), size);
    final overridden = await _render(card(override: true), const CardRefs(), size);

    expect(_firstDiff(base, overridden), isNot(-1),
        reason: 'a per-card fill override must change the render');
  });

  // -------------------------------------------------------------------------
  // 9-slice border aspect (per-edge insets + tile modes).
  //
  // Test card: white base + a border-aspect layer at _mid, so on the 200×280
  // card the layer rect is (60,84)-(140,196). With thickness 0.1 the thickest
  // band draws 20px (0.1 × 200). Sprites are 30×30 with colour-coded regions,
  // sampled well inside each drawn patch (away from filtered seams).
  // -------------------------------------------------------------------------

  const red = 0xFFFF0000;
  const green = 0xFF00FF00;
  const blue = 0xFF0000FF;
  const yellow = 0xFFFFFF00;

  Layer borderLayer(NineSliceSpec spec) =>
      Layer(id: 'frame', name: 'Frame', frac: _mid, border: spec);

  CardData frameCard(NineSliceSpec spec) => CardData(
        baseColor: _white,
        fields: const [],
        layers: [_baseFill(_white), borderLayer(spec)],
      );

  void expectColor(Uint8List px, int x, int y, int argb, String what,
      {int imgW = w}) {
    final (r, g, b, _) = _px(px, x, y, imgW);
    final er = (argb >> 16) & 0xFF, eg = (argb >> 8) & 0xFF, eb = argb & 0xFF;
    int lo(int c) => c > 127 ? 200 : -1;
    int hi(int c) => c > 127 ? 256 : 60;
    expect(r, allOf(greaterThan(lo(er)), lessThan(hi(er))), reason: '$what: R');
    expect(g, allOf(greaterThan(lo(eg)), lessThan(hi(eg))), reason: '$what: G');
    expect(b, allOf(greaterThan(lo(eb)), lessThan(hi(eb))), reason: '$what: B');
  }

  test('nine-slice: equal cuts draw fixed corners, edges, and center',
      () async {
    // Thirds: corners red, top/bottom edges green, left/right edges yellow,
    // center blue.
    final sprite = await _pxImage(30, 30, (x, y) {
      final xe = x < 10 || x >= 20; // in a horizontal band
      final ye = y < 10 || y >= 20; // in a vertical band
      if (xe && ye) return red;
      if (ye) return green;
      if (xe) return yellow;
      return blue;
    });
    const spec = NineSliceSpec(imageId: 'f', thickness: 0.1);
    final px = await _render(frameCard(spec), CardRefs(images: {'f': sprite}), size);

    expectColor(px, 68, 92, red, 'top-left corner (20px, fixed)');
    expectColor(px, 132, 188, red, 'bottom-right corner (20px, fixed)');
    expectColor(px, 100, 94, green, 'top edge');
    expectColor(px, 68, 140, yellow, 'left edge');
    expectColor(px, 100, 140, blue, 'center');
    expectColor(px, 30, 140, 0xFFFFFFFF, 'outside the layer stays white');
  });

  test('nine-slice: zero top/bottom cuts make a horizontal 3-slice', () async {
    // Vertical thirds only (uniform in y): red | green | blue.
    final sprite = await _pxImage(
        30, 30, (x, y) => x < 10 ? red : (x >= 20 ? blue : green));
    const spec = NineSliceSpec(
        imageId: 'f',
        insetL: 1 / 3,
        insetR: 1 / 3,
        insetT: 0,
        insetB: 0,
        thickness: 0.1);
    final px = await _render(frameCard(spec), CardRefs(images: {'f': sprite}), size);

    // The side bands span the FULL layer height — no top/bottom bands exist.
    expectColor(px, 68, 90, red, 'left band reaches the very top');
    expectColor(px, 68, 190, red, 'left band reaches the very bottom');
    expectColor(px, 132, 140, blue, 'right band');
    expectColor(px, 100, 90, green, 'center reaches the top (no top band)');
    expectColor(px, 100, 140, green, 'center middle');
  });

  test('nine-slice: asymmetric cuts draw proportionally thick bands',
      () async {
    // Horizontal bands matching the cuts: top 1/6 red, bottom 1/3 blue,
    // middle green. thickness 0.1 → bottom (the thickest cut) draws 20px,
    // top draws 10px (half the cut → half the thickness).
    final sprite = await _pxImage(
        30, 30, (x, y) => y < 5 ? red : (y >= 20 ? blue : green));
    const spec = NineSliceSpec(
        imageId: 'f',
        insetL: 0,
        insetR: 0,
        insetT: 1 / 6,
        insetB: 1 / 3,
        thickness: 0.1);
    final px = await _render(frameCard(spec), CardRefs(images: {'f': sprite}), size);

    expectColor(px, 100, 88, red, 'inside the 10px top band');
    expectColor(px, 100, 100, green, 'past the 10px top band (proportional)');
    expectColor(px, 100, 170, green, 'above the 20px bottom band');
    expectColor(px, 100, 186, blue, 'inside the 20px bottom band');
  });

  test('nine-slice: tiled edges and center render differently from stretched',
      () async {
    // Corners solid red; edge/center content varies per-pixel so tiling
    // (repeat at corner scale) can't coincide with stretching.
    const magenta = 0xFFFF00FF;
    final sprite = await _pxImage(30, 30, (x, y) {
      final xe = x < 10 || x >= 20;
      final ye = y < 10 || y >= 20;
      if (xe && ye) return red;
      return (x + y).isEven ? green : magenta;
    });
    NineSliceSpec spec(SliceFillMode m) => NineSliceSpec(
        imageId: 'f', thickness: 0.1, edgeMode: m, centerMode: m);
    final refs = CardRefs(images: {'f': sprite});

    final stretched =
        await _render(frameCard(spec(SliceFillMode.stretch)), refs, size);
    final tiled = await _render(frameCard(spec(SliceFillMode.tile)), refs, size);

    expect(_firstDiff(stretched, tiled), isNot(-1),
        reason: 'tile mode must sample the sprite differently from stretch');
  });

  test('nine-slice: fit equals tile when tiles divide the space exactly',
      () async {
    // Every number here is binary-exact so the identity holds with zero
    // floating-point noise: 32px sprite with 0.25 cuts (8px bands, 16px
    // middles), thickness 0.125 on a 200-wide card (25px drawn bands, edge
    // scale 25/8), so the ideal tile is exactly 50px. The layer fractions sit
    // on the 1/32 grid: rect (50,30)-(150,280) → horizontal runs 50 (1 tile),
    // vertical runs 200 (4 tiles). With nothing to cut off, fit's whole-tile
    // grid IS tile's centred grid.
    const magenta = 0xFFFF00FF;
    final sprite = await _pxImage(32, 32, (x, y) {
      final xe = x < 8 || x >= 24;
      final ye = y < 8 || y >= 24;
      if (xe && ye) return red;
      return (x + y).isEven ? green : magenta;
    });
    Layer layerWith(SliceFillMode m) => Layer(
        id: 'frame',
        name: 'Frame',
        frac: const ui.Rect.fromLTRB(0.25, 0.09375, 0.75, 0.875),
        border: NineSliceSpec(
            imageId: 'f',
            insetL: 0.25,
            insetT: 0.25,
            insetR: 0.25,
            insetB: 0.25,
            thickness: 0.125,
            edgeMode: m));
    CardData cardWith(SliceFillMode m) => CardData(
        baseColor: _white,
        fields: const [],
        layers: [_baseFill(_white), layerWith(m)]);
    final refs = CardRefs(images: {'f': sprite});
    const bigSize = ui.Size(200, 320);

    final tiled = await _render(cardWith(SliceFillMode.tile), refs, bigSize);
    final fitted = await _render(cardWith(SliceFillMode.fit), refs, bigSize);

    expect(_firstDiff(tiled, fitted), equals(-1),
        reason: 'an exact-multiple space makes fit and tile identical');
  });

  test('nine-slice: fit differs from tile and stretch on non-multiple spaces',
      () async {
    // The standard 200×280 card + _mid layer with default 0.33 cuts: the
    // ideal tile (~20.6px) divides neither the 40px horizontal runs nor the
    // 72px vertical ones — tile cuts partial tiles, fit squeezes whole ones
    // in, stretch doesn't repeat at all.
    const magenta = 0xFFFF00FF;
    final sprite = await _pxImage(30, 30, (x, y) {
      final xe = x < 10 || x >= 20;
      final ye = y < 10 || y >= 20;
      if (xe && ye) return red;
      return (x + y).isEven ? green : magenta;
    });
    NineSliceSpec spec(SliceFillMode m) => NineSliceSpec(
        imageId: 'f', thickness: 0.1, edgeMode: m, centerMode: m);
    final refs = CardRefs(images: {'f': sprite});

    final stretched =
        await _render(frameCard(spec(SliceFillMode.stretch)), refs, size);
    final tiled = await _render(frameCard(spec(SliceFillMode.tile)), refs, size);
    final fitted = await _render(frameCard(spec(SliceFillMode.fit)), refs, size);

    expect(_firstDiff(fitted, tiled), isNot(-1),
        reason: 'fit resizes tiles to fit whole; tile keeps size and cuts');
    expect(_firstDiff(fitted, stretched), isNot(-1),
        reason: 'fit repeats the pattern; stretch does not');
  });

  test('nine-slice: render is resolution-independent', () async {
    final sprite = await _pxImage(30, 30, (x, y) {
      final xe = x < 10 || x >= 20;
      final ye = y < 10 || y >= 20;
      if (xe && ye) return red;
      if (ye) return green;
      if (xe) return yellow;
      return blue;
    });
    const spec = NineSliceSpec(imageId: 'f', thickness: 0.1);
    final refs = CardRefs(images: {'f': sprite});

    final oneX = await _render(frameCard(spec), refs, size);
    final twoX =
        await _render(frameCard(spec), refs, const ui.Size(400, 560));

    // The same proportional points land in the same patches at both scales.
    expectColor(oneX, 68, 92, red, '1x corner');
    expectColor(twoX, 136, 184, red, '2x corner', imgW: 400);
    expectColor(oneX, 100, 94, green, '1x top edge');
    expectColor(twoX, 200, 188, green, '2x top edge', imgW: 400);
    expectColor(oneX, 100, 140, blue, '1x center');
    expectColor(twoX, 200, 280, blue, '2x center', imgW: 400);
  });
}
