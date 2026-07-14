// Sheet composition tests (rendering/sheet_export.dart + sheet_pdf.dart).
// Layout math is asserted with exact numbers; page rendering is verified at a
// tiny 30 dpi so tests stay fast while exercising the identical code path the
// real 300/600 dpi export uses (everything scales off dpi).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:cardboardpress/rendering/sheet_export.dart';
import 'package:cardboardpress/rendering/sheet_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = ColorRef.literal(ColorValue.single(ui.Color(0xFF0000FF)));
const _grey = ColorRef.literal(ColorValue.single(ui.Color(0xFF808080)));
const _full = ui.Rect.fromLTRB(0, 0, 1, 1);

CardData _solidCard(ColorRef c) => CardData(
      baseColor: c,
      fields: const [],
      layers: [
        Layer(id: 'base', name: 'Base', frac: _full, fill: FillAspect(color: c))
      ],
    );

Future<Uint8List> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = data!.buffer.asUint8List();
  frame.image.dispose();
  codec.dispose();
  return out;
}

Future<(int, int)> _pngDims(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final d = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return d;
}

(int, int, int) _rgbAt(Uint8List rgba, int x, int y, int imgW) {
  final i = (y * imgW + x) * 4;
  return (rgba[i], rgba[i + 1], rgba[i + 2]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layout math', () {
    test('A4 portrait, 5 mm margins, no gap: 3×3 of 2.5×3.5 in cards', () {
      final l = computeSheetLayout(
          const SheetSettings(dpi: 300, marginMm: 5, gapMm: 0), 2.5, 3.5);
      expect(l.cols, equals(3));
      expect(l.rows, equals(3));
      expect(l.perPage, equals(9));
      expect(l.cardW, equals(750));
      expect(l.cardH, equals(1050));
      expect(l.pageW, closeTo(2481, 0.01)); // 8.27 in × 300
      expect(l.originX, closeTo((2481 - 2250) / 2, 0.01));
      expect(l.originY, closeTo((3507 - 3150) / 2, 0.01));
    });

    test('Letter portrait, 5 mm margins, no gap: also 3×3', () {
      final l = computeSheetLayout(
          const SheetSettings(
              paper: SheetPaper.letter, dpi: 300, marginMm: 5, gapMm: 0),
          2.5,
          3.5);
      expect((l.cols, l.rows), equals((3, 3)));
    });

    test('A4 landscape: 4×2', () {
      final l = computeSheetLayout(
          const SheetSettings(
              landscape: true, dpi: 300, marginMm: 5, gapMm: 0),
          2.5,
          3.5);
      expect((l.cols, l.rows), equals((4, 2)));
    });

    test('a gap costs a column when it no longer fits', () {
      final l = computeSheetLayout(
          const SheetSettings(dpi: 300, marginMm: 5, gapMm: 5), 2.5, 3.5);
      expect(l.cols, equals(2),
          reason: '3 × 2.5in + 2 × 5mm gaps exceeds the usable A4 width');
    });

    test('cellRect walks the grid row-major', () {
      final l = computeSheetLayout(
          const SheetSettings(dpi: 300, marginMm: 5, gapMm: 0), 2.5, 3.5);
      final c4 = l.cellRect(4); // row 1, col 1 of the 3×3
      expect(c4.left, closeTo(l.originX + l.cardW, 0.01));
      expect(c4.top, closeTo(l.originY + l.cardH, 0.01));
    });

    test('an impossible fit throws instead of rendering an empty page', () {
      expect(
          () => computeSheetLayout(
              const SheetSettings(dpi: 300, marginMm: 100), 2.5, 3.5),
          throwsStateError);
    });
  });

  group('page rendering (30 dpi keeps it fast)', () {
    const settings =
        SheetSettings(dpi: 30, marginMm: 5, gapMm: 0, cutMarks: false);

    test('cards land in their cells; empty cells stay paper-white', () async {
      final pages = await composeSheetPages(
          [_solidCard(_blue), _solidCard(_grey)], CardRefs(), settings);
      expect(pages, hasLength(1));

      final (w, h) = await _pngDims(pages.single);
      expect((w, h), equals((248, 351))); // 8.27×11.69 in × 30, rounded

      final l = computeSheetLayout(settings, 2.5, 3.5);
      final rgba = await _decodeRgba(pages.single);
      (int, int) cellCenter(int i) {
        final c = l.cellRect(i).center;
        return (c.dx.round(), c.dy.round());
      }

      final (x0, y0) = cellCenter(0);
      expect(_rgbAt(rgba, x0, y0, w), equals((0, 0, 255)), reason: 'card 1');
      final (x1, y1) = cellCenter(1);
      expect(_rgbAt(rgba, x1, y1, w), equals((128, 128, 128)),
          reason: 'card 2');
      final (x2, y2) = cellCenter(2);
      expect(_rgbAt(rgba, x2, y2, w), equals((255, 255, 255)),
          reason: 'unused cell stays white');
      expect(_rgbAt(rgba, 2, 2, w), equals((255, 255, 255)),
          reason: 'margin stays white');
    });

    test('overflow continues onto further pages', () async {
      final cards = List<CardData>.filled(20, _solidCard(_blue));
      final pages = await composeSheetPages(cards, CardRefs(), settings);
      expect(pages, hasLength(3), reason: '9 per page → 9 + 9 + 2');
    });

    test('cut guides darken the trim line between shared edges', () async {
      final withMarks = await composeSheetPages([_solidCard(_blue)],
          CardRefs(), const SheetSettings(dpi: 30, marginMm: 5, gapMm: 0));
      final l = computeSheetLayout(settings, 2.5, 3.5);
      final rgba = await _decodeRgba(withMarks.single);
      // A point on the block's outer trim line, away from any card content.
      // The 1px guide sits at a FRACTIONAL y, so anti-aliasing splits its grey
      // across the two straddling pixel rows — sample both, judge the darker.
      final x = (l.originX + l.cardW * 1.5).round(); // top edge, over cell 1
      final a = _rgbAt(rgba, x, l.originY.floor(), 248);
      final b = _rgbAt(rgba, x, l.originY.ceil(), 248);
      final (r, g, bl) = a.$1 <= b.$1 ? a : b;
      expect(r, lessThan(240),
          reason: 'the majority-coverage row is clearly darker than paper');
      expect((r, g, bl), equals((r, r, r)), reason: 'guides are neutral grey');
    });
  });

  group('TTS sheets', () {
    test('small selection: gapless single-row grid at 1/10 sheet width',
        () async {
      final sheets = await composeTtsSheets(
          [_solidCard(_blue), _solidCard(_grey), _solidCard(_blue)],
          CardRefs());
      expect(sheets, hasLength(1));
      final s = sheets.single;
      expect((s.cols, s.rows), equals((3, 1)));
      final (w, h) = await _pngDims(s.png);
      expect(w, equals(3 * 409)); // floor(4096 / 10) per card
      expect(h, equals(573)); // 409 × 3.5/2.5, rounded
      final rgba = await _decodeRgba(s.png);
      expect(_rgbAt(rgba, 409 + 204, 286, w), equals((128, 128, 128)),
          reason: 'second cell holds the grey card');
    });

    test('more than 70 cards chunk into further sheets', () async {
      final cards = List<CardData>.filled(75, _solidCard(_blue));
      final sheets =
          await composeTtsSheets(cards, CardRefs(), maxSheetWidth: 200);
      expect(sheets, hasLength(2));
      expect((sheets[0].cols, sheets[0].rows), equals((10, 7)));
      expect((sheets[1].cols, sheets[1].rows), equals((5, 1)));
    });
  });

  test('PDF wrapper produces a PDF', () async {
    final pages = await composeSheetPages([_solidCard(_blue)], CardRefs(),
        const SheetSettings(dpi: 30, marginMm: 5));
    final pdf = await sheetPagesToPdf(pages, SheetPaper.a4);
    expect(String.fromCharCodes(pdf.take(5)), equals('%PDF-'));
  });
}
